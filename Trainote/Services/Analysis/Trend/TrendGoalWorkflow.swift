import Foundation

/// Revalidates proposals and invokes A's single atomic target/history transaction.
/// No preference save or append-then-project fallback is performed here.
@MainActor
struct TrendGoalWorkflow {
  typealias AtomicWriter = (ApplyGoalRevisionRequest) throws -> GoalRevisionApplicationResult
  let calculator: any TrendCalculating
  let write: AtomicWriter

  init(calculator: any TrendCalculating = TrendCalculator(), write: @escaping AtomicWriter) {
    self.calculator = calculator
    self.write = write
  }
  init(repository: any AnalysisRepository, calculator: any TrendCalculating = TrendCalculator()) {
    self.init(calculator: calculator, write: repository.applyGoalRevision)
  }

  @discardableResult
  func adopt(
    proposalID: String, input: AnalysisInput, expectedState: GoalRevisionState,
    automatically: Bool = false
  ) throws -> NutritionGoalRevisionValue {
    if let existing = input.goalHistory.first(where: { $0.proposalID == proposalID }) {
      guard !TrendHistory.isReversed(existing, history: input.goalHistory) else {
        throw AnalysisFailure.staleSnapshot
      }
      return existing
    }
    try validate(input, against: expectedState)
    guard input.preferences.goalMode != .manual,
      !automatically || (input.preferences.goalMode == .automatic && Self.hasAdoptedBaseline(input))
    else { throw AnalysisFailure.invalidInput }
    guard let proposal = try calculator.calculate(input).proposal, proposal.id == proposalID,
      proposal.previousTargets == input.currentManualTargets
    else { throw AnalysisFailure.staleSnapshot }
    let revision = NutritionGoalRevisionValue(
      id: Self.revisionID(proposal.id), effectiveAt: input.asOf, targets: proposal.targets,
      origin: automatically ? .automatic : .suggested, proposalID: proposal.id,
      calculationVersion: proposal.calculationVersion, createdAt: input.asOf)
    _ = try write(.init(revision: revision, expectedState: expectedState))
    return revision
  }

  static func hasAdoptedBaseline(_ input: AnalysisInput) -> Bool {
    TrendHistory.baseline(in: input) != nil
  }

  static func canUndo(_ revisionID: UUID, input: AnalysisInput) -> Bool {
    let history = TrendHistory.ordered(input.goalHistory)
    guard let latest = history.last else { return false }
    return history.count >= 2 && latest.id == revisionID && latest.origin != .manual
      && latest.reversesRevisionID == nil
      && !TrendHistory.isReversed(latest, history: history)
  }

  @discardableResult
  func undo(revisionID: UUID, input: AnalysisInput, expectedState: GoalRevisionState) throws
    -> NutritionGoalRevisionValue
  {
    try validate(input, against: expectedState)
    let history = TrendHistory.ordered(input.goalHistory)
    guard Self.canUndo(revisionID, input: input), let latest = history.last,
      latest.targets == input.currentManualTargets
    else { throw AnalysisFailure.staleSnapshot }
    let revision = NutritionGoalRevisionValue(
      id: Self.revisionID("trend-undo-\(latest.id.uuidString)"), effectiveAt: input.asOf,
      targets: history[history.count - 2].targets, origin: .manual,
      calculationVersion: latest.calculationVersion, reversesRevisionID: latest.id,
      createdAt: input.asOf)
    // The durable reversal itself pauses review for seven days. No separate preference write can fail
    // after target restoration, and the original proposal stays in history and can never be reapplied.
    _ = try write(.init(revision: revision, expectedState: expectedState))
    return revision
  }

  private func validate(_ input: AnalysisInput, against state: GoalRevisionState) throws {
    guard state.currentGoal?.targets == input.currentManualTargets,
      state.latestRevisionID == TrendHistory.ordered(input.goalHistory).last?.id,
      state.historyFingerprint
        == (try AnalysisFingerprint.digest(
          input.goalHistory.sorted {
            $0.id.uuidString < $1.id.uuidString
          }))
    else { throw GoalRevisionConflict.staleState }
    if let current = state.currentGoal, input.asOf <= current.updatedAt {
      throw GoalRevisionConflict.invalidChronology
    }
  }

  private static func revisionID(_ text: String) -> UUID {
    let digest = try! AnalysisFingerprint.digest(text)
    let bytes = Array(digest.prefix(32))
    let value =
      String(bytes[0..<8]) + "-" + String(bytes[8..<12]) + "-"
      + String(bytes[12..<16]) + "-" + String(bytes[16..<20]) + "-" + String(bytes[20..<32])
    return UUID(uuidString: value)!
  }
}
