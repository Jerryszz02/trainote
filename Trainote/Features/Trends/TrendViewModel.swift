import Foundation
import Observation

/// F supplies A's repository/health service and atomic writer. All UI mutations refresh their input.
@MainActor
@Observable
final class TrendViewModel {
  private(set) var input: AnalysisInput?
  private(set) var result: TrendResult?
  private(set) var records: ManualHealthRecords = .init()
  var errorMessage: String?
  private(set) var isLoading = false
  let repository: any AnalysisRepository
  let health: (any HealthDataProviding)?
  let calculator: any TrendCalculating
  let workflow: TrendGoalWorkflow?
  let now: () -> Date
  let timeZone: () -> TimeZone

  init(
    repository: any AnalysisRepository, health: (any HealthDataProviding)? = nil,
    calculator: any TrendCalculating = TrendCalculator(),
    atomicGoalWriter: TrendGoalWorkflow.AtomicWriter? = nil,
    now: @escaping () -> Date = { .now }, timeZone: @escaping () -> TimeZone = { .current }
  ) {
    self.repository = repository
    self.health = health
    self.calculator = calculator
    self.workflow = atomicGoalWriter.map { TrendGoalWorkflow(calculator: calculator, write: $0) }
    self.now = now
    self.timeZone = timeZone
  }
  var canApplyGoals: Bool { workflow != nil }
  var calendar: TrendCalendar { TrendCalendar(identifier: timeZone().identifier)! }
  var today: DailyNutrition? {
    input?.nutrition.first {
      $0.localDate == calendar.key(now()) && $0.timeZoneIdentifier == timeZone().identifier
    }
  }
  var nextReview: Date? {
    guard let input else { return nil }
    if let paused = input.preferences.pausedUntil, paused > now() { return paused }
    guard let last = TrendHistory.ordered(input.goalHistory).last else { return nil }
    return calendar.adding(days: 7, to: last.effectiveAt)
  }

  func reload(allowAutomaticAdoption: Bool = true) {
    errorMessage = nil
    isLoading = true
    defer { isLoading = false }
    do {
      try read()
      if allowAutomaticAdoption, let input, input.preferences.goalMode == .automatic,
        TrendGoalWorkflow.hasAdoptedBaseline(input),
        let proposal = result?.proposal, let workflow
      {
        try workflow.adopt(proposalID: proposal.id, input: input, automatically: true)
        try read()
      }
    } catch {
      // Keep values visible only as stale feedback; no action may use them until a fresh read succeeds.
      errorMessage = "读取或保存失败，请重试。原有记录和目标不会因这次失败而改变。"
    }
  }
  private func read() throws {
    let asOf = now()
    let zone = timeZone()
    let calendar = TrendCalendar(identifier: zone.identifier)!
    records = try repository.manualRecords()
    let firstManual = records.weights.map(\.measuredAt).min()
    let defaultStart = calendar.adding(days: -90, to: calendar.start(asOf))
    let window = AnalysisWindow(
      start: min(firstManual.map(calendar.start) ?? defaultStart, defaultStart),
      end: asOf.addingTimeInterval(0.001))
    let snapshot =
      try health?.localSnapshot(window: window) ?? .disconnected(window: window, asOf: asOf)
    let freshInput = try repository.analysisInput(
      asOf: asOf, window: window, timeZone: zone, health: snapshot)
    let freshResult = try calculator.calculate(freshInput)
    input = freshInput
    result = freshResult
  }
  private func mutate(_ operation: () throws -> Void) {
    errorMessage = nil
    do {
      try operation()
      reload(allowAutomaticAdoption: false)
    } catch {
      errorMessage = "未能保存，请检查输入并重试；当前目标未被改写。"
    }
  }
  func saveProfile(_ profile: BodyProfileValue) {
    mutate { try repository.saveProfile(profile) }
  }
  func saveWeight(id: UUID? = nil, date: Date, kilograms: Double) {
    mutate {
      guard date <= now() else { throw AnalysisFailure.invalidInput }
      let old = records.weights.first { $0.id == id }
      try repository.saveWeight(
        .init(
          id: id ?? UUID(), measuredAt: date, kilograms: kilograms,
          timeZoneIdentifier: old?.timeZoneIdentifier ?? timeZone().identifier,
          createdAt: old?.createdAt ?? now(), updatedAt: now()))
    }
  }
  func deleteWeight(_ id: UUID) { mutate { try repository.deleteWeight(id: id) } }
  func confirmDiet(on date: Date) {
    mutate {
      try read()
      let key = calendar.key(date)
      guard key <= calendar.key(now()) else { throw AnalysisFailure.invalidInput }
      let day = input?.nutrition.first { $0.localDate == key }
      let fingerprint = try day?.logFingerprint ?? AnalysisFingerprint.foodLogs([])
      let old = records.dietCompleteness.first {
        $0.localDate == key && $0.timeZoneIdentifier == timeZone().identifier
      }
      try repository.confirmDiet(
        .init(
          id: old?.id ?? UUID(), localDate: key,
          timeZoneIdentifier: timeZone().identifier, confirmedAt: now(),
          foodLogFingerprint: fingerprint))
    }
  }
  func setMode(_ mode: GoalMode) {
    mutate {
      var preferences = try repository.manualRecords().preferences
      preferences.goalMode = mode
      try repository.savePreferences(preferences)
    }
  }
  func pause(until date: Date?) {
    mutate {
      var preferences = try repository.manualRecords().preferences
      preferences.pausedUntil = date
      try repository.savePreferences(preferences)
    }
  }
  func preferSource(_ sourceID: String?) {
    mutate {
      var preferences = try repository.manualRecords().preferences
      preferences.preferredWeightSourceID = sourceID
      try repository.savePreferences(preferences)
    }
  }
  func selectWeight(_ sample: WeightSample) {
    mutate {
      var preferences = try repository.manualRecords().preferences
      let key = calendar.key(sample.measuredAt)
      preferences.weightSelections.removeAll {
        $0.localDate == key && $0.timeZoneIdentifier == timeZone().identifier
      }
      preferences.weightSelections.append(
        .init(
          localDate: key, timeZoneIdentifier: timeZone().identifier,
          sampleID: sample.id, source: sample.source))
      try repository.savePreferences(preferences)
    }
  }
  func adopt(_ proposalID: String) {
    mutate {
      guard let workflow else { throw AnalysisFailure.unavailable }
      try read()
      guard let input else { throw AnalysisFailure.unavailable }
      try workflow.adopt(proposalID: proposalID, input: input)
    }
  }
  func undo(_ revisionID: UUID) {
    mutate {
      guard let workflow else { throw AnalysisFailure.unavailable }
      try read()
      guard let input else { throw AnalysisFailure.unavailable }
      try workflow.undo(revisionID: revisionID, input: input)
    }
  }
}
