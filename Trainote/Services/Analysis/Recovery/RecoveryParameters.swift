import Foundation

/// All constants are versioned engineering priors, not physiological measurements.
enum RecoveryParameters {
  static let version = "recovery-v0.1"
  static let historyDays = 28
  static let inputDays = 90
  static let tauHours = 36.0
  static let loadScale = 6.0
  static let effortWeights = [1.25, 1.15, 1.05, 1.0, 0.85, 0.70]
  static func effort(rir: Int?) -> Double {
    guard let rir, effortWeights.indices.contains(rir) else { return 1 }
    return effortWeights[rir]
  }
  static func score(residualLoad: Double) -> Double {
    100 * exp(-max(0, residualLoad) / loadScale)
  }
  static func displayedScore(_ score: Double) -> Int { Int((score / 5).rounded()) * 5 }
  static func state(score: Double?) -> RecoveryState {
    guard let score else { return .unknown }
    switch displayedScore(score) {
    case 80...100: return .ready
    case 50..<80: return .moderate
    default: return .low
    }
  }
}

struct RecoveryLoadSession: Equatable, Sendable {
  var workoutID: UUID
  var endedAt: Date
  var load: [MuscleID: Double]
  var quality: [DataQualityFlag]
  var dependencies: [SourceDependency]
}

/// Sorting keeps array order and encoded reports deterministic.
enum RecoveryEvidence {
  static func dependencies(_ values: [SourceDependency]) -> [SourceDependency] {
    Array(Set(values)).sorted {
      let a = "\($0.kind.rawValue)|\($0.id)|\($0.healthType?.rawValue ?? "")"
      let b = "\($1.kind.rawValue)|\($1.id)|\($1.healthType?.rawValue ?? "")"
      return a < b
    }
  }
  static func quality(_ values: [DataQualityFlag]) -> [DataQualityFlag] {
    Array(Set(values.map(\.rawValue))).sorted().compactMap(DataQualityFlag.init(rawValue:))
  }
  static func sources(_ facts: [MetricFact]) -> [DataSource] {
    Array(Set(facts.flatMap(\.sources))).sorted {
      "\($0.kind.rawValue)|\($0.identifier)|\($0.version ?? "")"
        < "\($1.kind.rawValue)|\($1.identifier)|\($1.version ?? "")"
    }
  }
}
