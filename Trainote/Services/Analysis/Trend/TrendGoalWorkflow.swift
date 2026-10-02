import Foundation

/// Orchestrates shared values. The injected writer MUST atomically compare expected state, preserve
/// the first legacy baseline, append an immutable revision, and project NutritionGoal/preferences.
/// A owns that transaction; there is deliberately no append-then-save fallback here.
@MainActor
struct TrendGoalWorkflow {
  typealias AtomicWriter = (
    _ revision: NutritionGoalRevisionValue,
    _ expectedTargets: NutritionTargets?,
    _ expectedLatestRevisionID: UUID?,
    _ preferences: AnalysisPreferencesValue?
  ) throws -> Void
  let calculator: any TrendCalculating
  let write: AtomicWriter

  init(calculator: any TrendCalculating = TrendCalculator(), write: @escaping AtomicWriter) {
    self.calculator = calculator
    self.write = write
  }

  @discardableResult
  func adopt(proposalID: String, input: AnalysisInput, automatically: Bool = false) throws
    -> NutritionGoalRevisionValue
  {
    if let existing = input.goalHistory.first(where: { $0.proposalID == proposalID }) {
      guard !TrendHistory.isReversed(existing, history: input.goalHistory) else {
        throw AnalysisFailure.staleSnapshot
      }
      return existing
    }
    guard input.preferences.goalMode != .manual,
      !automatically || (input.preferences.goalMode == .automatic && Self.hasAdoptedBaseline(input))
    else {
      throw AnalysisFailure.invalidInput
    }
    guard let proposal = try calculator.calculate(input).proposal, proposal.id == proposalID,
      proposal.previousTargets == input.currentManualTargets
    else { throw AnalysisFailure.staleSnapshot }
    let revision = NutritionGoalRevisionValue(
      id: Self.revisionID(proposal.id), effectiveAt: proposal.effectiveAt,
      targets: proposal.targets,
      origin: automatically ? .automatic : .suggested, proposalID: proposal.id,
      calculationVersion: proposal.calculationVersion,
      createdAt: max(
        input.asOf,
        TrendHistory.ordered(input.goalHistory).last?.createdAt
          .addingTimeInterval(0.001) ?? input.asOf))
    try write(
      revision, input.currentManualTargets,
      TrendHistory.ordered(input.goalHistory).last?.id, nil)
    return revision
  }

  static func hasAdoptedBaseline(_ input: AnalysisInput) -> Bool {
    input.goalHistory.contains {
      $0.calculationVersion == TrendRules().version && $0.reversesRevisionID == nil
    }
  }

  @discardableResult
  func undo(revisionID: UUID, input: AnalysisInput) throws -> NutritionGoalRevisionValue {
    let history = TrendHistory.ordered(input.goalHistory)
    guard let latest = history.last, latest.id == revisionID, latest.origin != .manual,
      latest.reversesRevisionID == nil, history.count >= 2,
      !TrendHistory.isReversed(latest, history: history),
      latest.targets == input.currentManualTargets,
      let calendar = TrendCalendar(identifier: input.calendarTimeZone)
    else {
      throw AnalysisFailure.staleSnapshot
    }
    let id = "trend-undo-\(latest.id.uuidString)"
    let revision = NutritionGoalRevisionValue(
      id: Self.revisionID(id), effectiveAt: calendar.start(input.asOf),
      targets: history[history.count - 2].targets, origin: .manual, proposalID: id,
      calculationVersion: latest.calculationVersion, reversesRevisionID: latest.id,
      createdAt: max(input.asOf, latest.createdAt.addingTimeInterval(0.001)))
    var preferences = input.preferences
    // Undo explicitly returns to user adoption, preventing changed fingerprints from reapplying it.
    preferences.goalMode = .suggested
    preferences.pausedUntil = calendar.adding(days: 7, to: calendar.start(input.asOf))
    try write(revision, input.currentManualTargets, latest.id, preferences)
    return revision
  }

  private static func revisionID(_ text: String) -> UUID {
    // Stable proposal IDs contain SHA-256; undo IDs contain UUIDs. Hash both into a stable UUID.
    let digest = try! AnalysisFingerprint.digest(text)
    let bytes = Array(digest.prefix(32))
    let value =
      String(bytes[0..<8]) + "-" + String(bytes[8..<12]) + "-"
      + String(bytes[12..<16]) + "-" + String(bytes[16..<20]) + "-" + String(bytes[20..<32])
    return UUID(uuidString: value)!
  }
}
