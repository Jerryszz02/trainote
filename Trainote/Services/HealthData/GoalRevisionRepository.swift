import Foundation
import SwiftData

extension SwiftDataAnalysisRepository {
  func goalRevisionState() throws -> GoalRevisionState {
    try goalRecords(in: ModelContext(container)).state
  }

  /// Adopting/reversing a target is one isolated save. No asynchronous work occurs between the
  /// optimistic-state check and commit, and an exact request replay never reapplies an old target.
  func applyGoalRevision(_ request: ApplyGoalRevisionRequest) throws
    -> GoalRevisionApplicationResult
  {
    let revision = request.revision
    try ManualRecordValidation.validate(revision)
    let context = ModelContext(container)
    context.autosaveEnabled = false
    do {
      let records = try goalRecords(in: context)
      if let existing = records.history.first(where: { $0.id == revision.id }) {
        guard existing == revision else { throw GoalRevisionConflict.revisionIDConflict }
        return .init(
          state: records.state, appliedRevisionID: existing.id,
          insertedBaselineRevisionID: nil, wasAlreadyApplied: true)
      }
      if let proposalID = revision.proposalID,
        records.history.contains(where: { $0.proposalID == proposalID })
      {
        throw GoalRevisionConflict.duplicateProposal
      }
      if let reversedID = revision.reversesRevisionID,
        records.history.contains(where: { $0.reversesRevisionID == reversedID })
      {
        throw GoalRevisionConflict.alreadyReversed
      }
      guard request.expectedState == records.state else { throw GoalRevisionConflict.staleState }
      guard revision.effectiveAt <= revision.createdAt else {
        throw GoalRevisionConflict.invalidChronology
      }
      if let latest = records.history.last {
        // Existing manual editors must use this API too once history exists. Detect unrecorded
        // writes instead of restoring a target that was never the predecessor of this adoption.
        guard records.state.currentGoal?.targets == latest.targets,
          records.state.currentGoal?.updatedAt == latest.createdAt
        else {
          throw GoalRevisionConflict.inconsistentHistory
        }
        guard revision.createdAt > latest.createdAt, revision.effectiveAt >= latest.effectiveAt
        else {
          throw GoalRevisionConflict.invalidChronology
        }
      } else if let current = records.state.currentGoal {
        guard revision.createdAt > current.updatedAt, revision.effectiveAt > current.updatedAt
        else {
          throw GoalRevisionConflict.invalidChronology
        }
      }
      if let reversedID = revision.reversesRevisionID {
        guard records.history.count >= 2,
          let latest = records.history.last, latest.id == reversedID,
          latest.reversesRevisionID == nil,
          revision.targets == records.history[records.history.count - 2].targets,
          revision.origin == .manual, revision.proposalID == nil
        else {
          throw GoalRevisionConflict.invalidReversal
        }
      }

      var history = records.history
      var baselineID: UUID?
      if history.isEmpty, let current = records.state.currentGoal {
        try ManualRecordValidation.validate(current.targets)
        let baseline = NutritionGoalRevisionValue(
          id: UUID(), effectiveAt: current.updatedAt,
          targets: current.targets, origin: .manual, createdAt: revision.createdAt)
        context.insert(NutritionGoalRevision(value: baseline))
        history.append(baseline)
        baselineID = baseline.id
      }
      let current =
        records.current
        ?? NutritionGoal(
          calories: revision.targets.calories, carbohydrates: revision.targets.carbohydrates,
          protein: revision.targets.protein, fat: revision.targets.fat,
          updatedAt: revision.createdAt)
      if records.current == nil { context.insert(current) }
      current.calories = revision.targets.calories
      current.carbohydrates = revision.targets.carbohydrates
      current.protein = revision.targets.protein
      current.fat = revision.targets.fat
      current.updatedAt = revision.createdAt
      context.insert(NutritionGoalRevision(value: revision))
      history.append(revision)
      // Compute the result before committing so a later read/encoding failure cannot report a
      // failed application after data was already saved.
      let state = GoalRevisionState(
        currentGoal: currentSnapshot(current), latestRevisionID: revision.id,
        historyFingerprint: try historyFingerprint(history))
      let result = GoalRevisionApplicationResult(
        state: state, appliedRevisionID: revision.id,
        insertedBaselineRevisionID: baselineID, wasAlreadyApplied: false)
      try context.save()
      return result
    } catch {
      context.rollback()
      throw error
    }
  }

  private func goalRecords(in context: ModelContext) throws -> (
    current: NutritionGoal?, history: [NutritionGoalRevisionValue], state: GoalRevisionState
  ) {
    let goals = try context.fetch(FetchDescriptor<NutritionGoal>()).sorted {
      $0.updatedAt == $1.updatedAt
        ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
    }
    if let first = goals.first,
      goals.dropFirst().contains(where: {
        $0.updatedAt == first.updatedAt
          && currentSnapshot($0).targets != currentSnapshot(first).targets
      })
    {
      throw GoalRevisionConflict.ambiguousCurrentGoal
    }
    let history = try context.fetch(FetchDescriptor<NutritionGoalRevision>()).map(\.value).sorted {
      if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
      if $0.effectiveAt != $1.effectiveAt { return $0.effectiveAt < $1.effectiveAt }
      return $0.id.uuidString < $1.id.uuidString
    }
    let state = GoalRevisionState(
      currentGoal: goals.first.map(currentSnapshot),
      latestRevisionID: history.last?.id, historyFingerprint: try historyFingerprint(history))
    return (goals.first, history, state)
  }

  private func currentSnapshot(_ goal: NutritionGoal) -> CurrentNutritionGoalSnapshot {
    .init(
      id: goal.id,
      targets: .init(
        calories: goal.calories, carbohydrates: goal.carbohydrates, protein: goal.protein,
        fat: goal.fat),
      updatedAt: goal.updatedAt)
  }

  private func historyFingerprint(_ values: [NutritionGoalRevisionValue]) throws -> String {
    try AnalysisFingerprint.digest(values.sorted { $0.id.uuidString < $1.id.uuidString })
  }
}
