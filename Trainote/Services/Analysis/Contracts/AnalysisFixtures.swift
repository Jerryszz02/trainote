import Foundation

/// Synthetic, deterministic fixtures. Never read the user's store, clock, HealthKit or network.
enum AnalysisFixtures {
  enum Scenario: CaseIterable {
    case complete, missingHRV, manualOnly, unknownExercise, aiDeclined, overnightSleep
    case duplicateHealthSources
  }
  static let asOf = Date(timeIntervalSince1970: 1_791_072_000)
  static let window = AnalysisWindow(start: asOf.addingTimeInterval(-21 * 86_400), end: asOf)
  static let watch = HealthSource(bundleIdentifier: "fixture.watch", name: "Synthetic Watch")
  static let phone = HealthSource(bundleIdentifier: "fixture.phone", name: "Synthetic Phone")
  static func id(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
  }
  static func health(_ scenario: Scenario) -> HealthDataSnapshot {
    var samples: [HealthSample] = []
    if scenario != .manualOnly {
      samples = [
        .init(
          id: id(1), type: .bodyMass, start: asOf.addingTimeInterval(-3600),
          end: asOf.addingTimeInterval(-3600), value: 70, unit: .kilograms, source: watch),
        .init(
          id: id(2), type: .sleep, start: asOf.addingTimeInterval(-9 * 3600),
          end: asOf.addingTimeInterval(-3600), value: nil, unit: .seconds,
          source: watch, timeZoneIdentifier: "Asia/Shanghai", sleepStage: .core),
        .init(
          id: id(3), type: .restingHeartRate, start: asOf.addingTimeInterval(-3600),
          end: asOf.addingTimeInterval(-3600), value: 60, unit: .beatsPerMinute, source: watch),
      ]
      if scenario != .missingHRV {
        samples.append(
          .init(
            id: id(4), type: .heartRateVariabilitySDNN,
            start: asOf.addingTimeInterval(-3600), end: asOf.addingTimeInterval(-3600),
            value: 40, unit: .milliseconds, source: watch, definition: "SDNN",
            measurementContext: "unspecified"))
      }
      if scenario == .duplicateHealthSources {
        var duplicate = samples[1]
        duplicate.id = id(5)
        duplicate.source = phone
        samples.append(duplicate)
        samples.append(
          .init(
            id: id(6), type: .sleep, start: samples[1].start,
            end: samples[1].end, value: nil, unit: .seconds,
            source: watch, sleepStage: .inBed))
        for (n, source) in [(7, watch), (8, phone)] {
          samples.append(
            .init(
              id: id(n), type: .steps, start: asOf.addingTimeInterval(-3600),
              end: asOf, value: 1000, unit: .count, source: source))
        }
      }
    }
    return .init(
      window: window, fetchedAt: asOf, isFresh: true, samples: samples,
      statuses: HealthDataType.allCases.map { type in
        .init(
          type: type, state: samples.contains { $0.type == type } ? .samplesAvailable : .noSamples,
          queriedAt: asOf)
      })
  }
  static func input(_ scenario: Scenario = .complete) -> AnalysisInput {
    let healthSnapshot = health(scenario)
    let days = (0..<21).map { offset -> DailyNutrition in
      let date = window.start.addingTimeInterval(Double(offset) * 86_400)
      let formatter = DateFormatter()
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = "yyyy-MM-dd"
      return .init(
        localDate: formatter.string(from: date), timeZoneIdentifier: "UTC",
        totals: .init(calories: 2000, carbohydrates: 240, protein: 120, fat: 60),
        logIDs: [id(100 + offset)], logFingerprint: "fixture-food-\(offset)", isComplete: true)
    }
    return .init(
      asOf: asOf, calendarTimeZone: "UTC", inputFingerprint: "fixture-\(scenario)",
      profile: .init(
        id: id(9), heightCentimeters: 175, ageYears: 30, formulaSex: .male,
        activityLevel: .moderate, goalDirection: .maintain,
        trainingDaysPerWeek: 3, isAdultGeneralFitness: true, updatedAt: asOf),
      workouts: [
        .init(
          id: id(10), startedAt: asOf.addingTimeInterval(-86_400),
          endedAt: asOf.addingTimeInterval(-82_800), isCompleted: true,
          exercises: [
            .init(
              id: id(11),
              sourceExerciseID: scenario == .unknownExercise ? "unknown-fixture" : "0025",
              trackingMode: "strength",
              sets: [
                .init(
                  id: id(12), orderIndex: 0,
                  weightKilograms: 60, repetitions: 8, durationSeconds: 0,
                  isCompleted: true, rir: 2, role: .working)
              ])
          ])
      ],
      nutrition: days,
      weights: (0..<21).map { offset in
        .init(
          id: id(200 + offset),
          measuredAt: window.start.addingTimeInterval(Double(offset) * 86_400),
          kilograms: 70, timeZoneIdentifier: "UTC", source: .manual)
      },
      health: .init(
        window: window, facts: [], externalWorkouts: [], statuses: healthSnapshot.statuses),
      checkIns: [
        .init(
          id: id(13), localDate: days.last!.localDate, timeZoneIdentifier: "UTC",
          feeling: .normal,
          muscleFeedback: [
            .init(
              id: id(14), muscleID: .chest,
              soreness: .mild, hasPain: false, recordedAt: asOf)
          ], updatedAt: asOf)
      ])
  }
  static var bodyMap: BodyMapPresentation { BodyMapFixtures.populated }
  static var trend: TrendResult {
    .init(
      inputFingerprint: "fixture-complete", points: [], weeklyChangeKilograms: nil,
      weeklyChangePercent: nil, proposal: nil, holdReason: .baselineBuilding, facts: [],
      calculationVersion: "synthetic-fixture-v1")
  }
  static var recovery: RecoveryResult {
    .init(
      inputFingerprint: "fixture-complete", asOf: asOf,
      muscles: bodyMap.muscles.map {
        .init(muscleID: $0.muscleID, score: $0.score, state: $0.state)
      },
      systemicState: .unknown, systemicFactIDs: [], facts: [],
      calculationVersion: "synthetic-fixture-v1")
  }
  static var report: ReportInput {
    .init(
      reportType: .today, asOf: asOf, inputFingerprint: "fixture-complete", facts: [],
      candidates: [
        .init(
          actionID: "fixture.choosePlan", action: .choosePlan,
          muscleIDs: [], reasonFactIDs: [])
      ],
      goalDirection: .maintain, knowledgeVersion: "synthetic-fixture-v1",
      calculationVersions: [], missingData: ["healthBaseline"])
  }
}

@MainActor
final class FixtureHealthDataProvider: HealthDataProviding {
  var snapshot: HealthDataSnapshot
  var failure: AnalysisFailure?
  private(set) var authorizationRequests = 0
  private(set) var freshRequests = 0
  private(set) var isDisconnected = false
  init(scenario: AnalysisFixtures.Scenario = .complete) {
    snapshot = AnalysisFixtures.health(scenario)
  }
  func requestReadAuthorization() async throws {
    authorizationRequests += 1
    if let failure { throw failure }
    isDisconnected = false
  }
  func startObserving() async throws { if let failure { throw failure } }
  func refresh() async throws { if let failure { throw failure } }
  func localSnapshot(window: AnalysisWindow) throws -> HealthDataSnapshot {
    if let failure { throw failure }
    if isDisconnected { return .disconnected(window: window, asOf: snapshot.fetchedAt) }
    var copy = snapshot
    copy.window = window
    copy.isFresh = false
    return copy
  }
  func freshSnapshot(window: AnalysisWindow, timeZone: TimeZone) async throws -> HealthDataSnapshot
  {
    freshRequests += 1
    var copy = try localSnapshot(window: window)
    copy.isFresh = true
    return copy
  }
  func disconnectAndDelete() async throws {
    isDisconnected = true
    snapshot = .disconnected(window: snapshot.window, asOf: snapshot.fetchedAt)
  }
}
struct FixtureTrendCalculator: TrendCalculating {
  func calculate(_ input: AnalysisInput) throws -> TrendResult {
    var result = AnalysisFixtures.trend
    result.inputFingerprint = input.inputFingerprint
    return result
  }
}
struct FixtureRecoveryCalculator: RecoveryCalculating {
  func calculate(_ input: AnalysisInput) throws -> RecoveryResult {
    var result = AnalysisFixtures.recovery
    result.inputFingerprint = input.inputFingerprint
    result.asOf = input.asOf
    return result
  }
}
struct FixtureRecommendationProvider: RecommendationProviding {
  func candidates(input: AnalysisInput, trend: TrendResult, recovery: RecoveryResult) throws
    -> [RecommendationCandidate]
  { AnalysisFixtures.report.candidates }
}
struct FixtureReportGenerator: ReportGenerating {
  func generate(_ input: ReportInput) async throws -> ReportResult {
    .init(
      reportID: "fixture-report", inputFingerprint: input.inputFingerprint, model: "fixture",
      promptVersion: "fixture-v1", summary: "合成数据示例", observations: [],
      recommendations: [], generatedAt: input.asOf, validUntil: input.asOf.addingTimeInterval(3600),
      isLocalFallback: true)
  }
}
