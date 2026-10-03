import Foundation

enum HealthDataType: String, Codable, CaseIterable, Sendable {
  case bodyMass, sleep, restingHeartRate, heartRateVariabilitySDNN, steps, activeEnergy, workout
}
enum HealthReadState: String, Codable, Sendable {
  /// HealthKit does not disclose per-type read authorization. Empty is not denied.
  case unknown, samplesAvailable, noSamples, failed, disconnected, unavailable
}
enum SleepStage: String, Codable, Sendable {
  case inBed, awake, asleepUnspecified, core, deep, rem
  var isAsleep: Bool { self != .inBed && self != .awake }
}
struct HealthSource: Codable, Equatable, Hashable, Sendable {
  var bundleIdentifier: String
  var name: String
  var version: String? = nil
  var productType: String? = nil
  var dataSource: DataSource {
    .init(kind: .healthKit, identifier: bundleIdentifier, version: version)
  }
}
struct HealthSample: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var type: HealthDataType
  var start: Date
  var end: Date
  var value: Double?
  var unit: MetricUnit
  var source: HealthSource
  var timeZoneIdentifier: String? = nil
  var sleepStage: SleepStage? = nil
  /// e.g. SDNN; never combine SDNN and RMSSD into a single baseline.
  var definition: String? = nil
  var measurementContext: String? = nil
  var workoutActivityCode: UInt? = nil
}
struct HealthReadStatus: Codable, Equatable, Sendable {
  var type: HealthDataType
  var state: HealthReadState
  var queriedAt: Date
  var failure: AnalysisFailure? = nil
}
struct HealthDataSnapshot: Codable, Equatable, Sendable {
  var window: AnalysisWindow
  var fetchedAt: Date
  /// A fresh query of this exact window, not an anchored cache replay.
  var isFresh: Bool
  var samples: [HealthSample]
  var statuses: [HealthReadStatus]
  var activityFacts: [MetricFact] = []
  static func disconnected(window: AnalysisWindow, asOf: Date) -> Self {
    .init(
      window: window, fetchedAt: asOf, isFresh: true, samples: [],
      statuses: HealthDataType.allCases.map {
        .init(type: $0, state: .disconnected, queriedAt: asOf)
      })
  }
}
struct ExternalWorkoutSummary: Codable, Equatable, Identifiable, Sendable {
  var id: UUID
  var start: Date
  var end: Date
  var activityCode: UInt?
  var source: DataSource
  var possibleDuplicateIDs: [UUID]
  /// Timeline/systemic context only. There is intentionally no local muscle/set count.
}
struct HealthSummary: Codable, Equatable, Sendable {
  var window: AnalysisWindow
  var facts: [MetricFact]
  var externalWorkouts: [ExternalWorkoutSummary]
  var statuses: [HealthReadStatus]
  static func empty(window: AnalysisWindow) -> Self {
    .init(window: window, facts: [], externalWorkouts: [], statuses: [])
  }
}
@MainActor
protocol HealthDataProviding {
  func requestReadAuthorization() async throws
  func startObserving() async throws
  func refresh() async throws
  func localSnapshot(window: AnalysisWindow) throws -> HealthDataSnapshot
  func freshSnapshot(window: AnalysisWindow, timeZone: TimeZone) async throws -> HealthDataSnapshot
  func disconnectAndDelete() async throws
}

extension HealthDataProviding {
  func freshSnapshot(window: AnalysisWindow) async throws -> HealthDataSnapshot {
    try await freshSnapshot(window: window, timeZone: .current)
  }
}
