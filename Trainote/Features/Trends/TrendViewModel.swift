import Foundation
import Observation

/// F supplies A's repository/health service. All target writes use its atomic revision API.
@MainActor
@Observable
final class TrendViewModel {
  private(set) var input: AnalysisInput?
  private(set) var result: TrendResult?
  private(set) var goalState: GoalRevisionState?
  private(set) var records: ManualHealthRecords = .init()
  var errorMessage: String?
  private(set) var isLoading = false
  let repository: any AnalysisRepository
  let health: (any HealthDataProviding)?
  let calculator: any TrendCalculating
  let workflow: TrendGoalWorkflow
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
    self.workflow = TrendGoalWorkflow(
      calculator: calculator,
      write: atomicGoalWriter ?? repository.applyGoalRevision)
    self.now = now
    self.timeZone = timeZone
  }
  var canApplyGoals: Bool { goalState != nil && errorMessage == nil }
  var calendar: TrendCalendar { TrendCalendar(identifier: timeZone().identifier)! }
  var today: DailyNutrition? {
    input?.nutrition.first {
      $0.localDate == calendar.key(now()) && $0.timeZoneIdentifier == timeZone().identifier
    }
  }
  var nextReview: Date? {
    guard let input else { return nil }
    var dates: [Date] = []
    if let paused = input.preferences.pausedUntil { dates.append(paused) }
    if let last = TrendHistory.ordered(input.goalHistory).last {
      dates.append(calendar.adding(days: 7, to: last.effectiveAt))
    }
    if TrendHistory.needsBaselineRebuild(input), let profile = input.profile {
      dates.append(calendar.adding(days: 7, to: profile.updatedAt))
    }
    return dates.max()
  }

  func reload(allowAutomaticAdoption: Bool = true) {
    errorMessage = nil
    isLoading = true
    defer { isLoading = false }
    do { try read() } catch {
      goalState = nil
      errorMessage = "读取失败，请刷新后重试。"
      return
    }
    do {
      if allowAutomaticAdoption, let input, input.preferences.goalMode == .automatic,
        TrendGoalWorkflow.hasAdoptedBaseline(input),
        let proposal = result?.proposal, let goalState
      {
        try workflow.adopt(
          proposalID: proposal.id, input: input, expectedState: goalState, automatically: true)
        refreshAfterCommit()
      }
    } catch {
      errorMessage = "本次目标未能保存，请刷新后重试。"
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
    goalState = try repository.goalRevisionState()
    input = freshInput
    result = freshResult
  }
  @discardableResult
  private func mutate(_ operation: () throws -> Void) -> Bool {
    errorMessage = nil
    do {
      try operation()
    } catch {
      errorMessage =
        error is GoalRevisionConflict
        ? "目标状态已变化或需要复核，请刷新后重新确认。"
        : "未能完成操作，请检查输入并重试。"
      return false
    }
    refreshAfterCommit()
    return true
  }
  private func refreshAfterCommit() {
    do { try read() } catch {
      goalState = nil
      errorMessage = "已保存，但显示尚未刷新。请刷新页面核对，无需再次保存。"
    }
  }
  @discardableResult
  func saveProfile(_ profile: BodyProfileValue) -> Bool {
    mutate { try repository.saveProfile(profile) }
  }
  @discardableResult
  func saveWeight(id: UUID? = nil, date: Date, kilograms: Double) -> Bool {
    return mutate {
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
  @discardableResult
  func adopt(_ proposalID: String) -> Bool {
    let expected = goalState
    return mutate {
      guard let expected else { throw AnalysisFailure.unavailable }
      try read()
      guard let input else { throw AnalysisFailure.unavailable }
      try workflow.adopt(proposalID: proposalID, input: input, expectedState: expected)
    }
  }
  @discardableResult
  func undo(_ revisionID: UUID) -> Bool {
    let expected = goalState
    return mutate {
      guard let expected else { throw AnalysisFailure.unavailable }
      try read()
      guard let input else { throw AnalysisFailure.unavailable }
      try workflow.undo(revisionID: revisionID, input: input, expectedState: expected)
    }
  }
}
