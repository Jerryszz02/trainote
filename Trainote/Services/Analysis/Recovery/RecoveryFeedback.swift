import Foundation

struct RecoveryFeedback {
  struct Muscle {
    var soreness: SorenessLevel?
    var hasPain: Bool?
    var hasMovementLimitation: Bool?
    var sorenessFactIDs: [String] = []
    var constraintFactIDs: [String] = []
  }
  var muscles: [MuscleID: Muscle] = [:]
  var feeling: OverallFeeling?
  var sleepFeeling: SleepFeeling?
  var facts: [MetricFact] = []

  init(input: AnalysisInput) {
    let checks = input.checkIns.filter {
      $0.updatedAt <= input.asOf && $0.updatedAt.timeIntervalSince1970.isFinite
    }.sorted {
      $0.updatedAt == $1.updatedAt
        ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt < $1.updatedAt
    }
    func isToday(_ check: CheckInValue) -> Bool {
      guard let zone = TimeZone(identifier: check.timeZoneIdentifier) else { return false }
      return check.localDate == AnalysisFingerprint.localDate(input.asOf, timeZone: zone)
    }
    let today = checks.filter(isToday)
    if let check = today.last(where: { $0.feeling != nil }) {
      feeling = check.feeling
      facts.append(
        Self.fact(
          id: "recovery.feeling",
          value: check.feeling == .good ? 2 : (check.feeling == .normal ? 1 : 0),
          date: check.updatedAt, recordID: check.id))
    }
    if let check = today.last(where: { $0.sleepFeeling != nil }) {
      sleepFeeling = check.sleepFeeling
      facts.append(
        Self.fact(
          id: "recovery.sleepFeeling",
          value: check.sleepFeeling == .good ? 2 : (check.sleepFeeling == .normal ? 1 : 0),
          date: check.updatedAt, recordID: check.id))
    }
    let all = checks.flatMap(\.muscleFeedback).filter { $0.recordedAt <= input.asOf }
      .sorted {
        $0.recordedAt == $1.recordedAt
          ? $0.id.uuidString < $1.id.uuidString : $0.recordedAt < $1.recordedAt
      }
    let current = today.flatMap(\.muscleFeedback).filter { $0.recordedAt <= input.asOf }
      .sorted {
        $0.recordedAt == $1.recordedAt
          ? $0.id.uuidString < $1.id.uuidString : $0.recordedAt < $1.recordedAt
      }
    for muscle in MuscleID.allCases {
      var value = Muscle()
      if let response = current.last(where: { $0.muscleID == muscle && $0.soreness != nil }) {
        value.soreness = response.soreness
        let id = "recovery.\(muscle.rawValue).soreness"
        value.sorenessFactIDs = [id]
        facts.append(
          Self.fact(
            id: id,
            value: response.soreness == .significant ? 2 : (response.soreness == .mild ? 1 : 0),
            date: response.recordedAt, recordID: response.id))
      }
      // Unanswered is not a negative answer. Constraints remain until explicitly cleared.
      if let response = all.last(where: { $0.muscleID == muscle && $0.hasPain != nil }) {
        value.hasPain = response.hasPain
        let id = "recovery.\(muscle.rawValue).pain"
        value.constraintFactIDs.append(id)
        facts.append(
          Self.fact(
            id: id, value: response.hasPain == true ? 1 : 0,
            date: response.recordedAt, recordID: response.id))
      }
      if let response = all.last(where: { $0.muscleID == muscle && $0.hasMovementLimitation != nil }
      ) {
        value.hasMovementLimitation = response.hasMovementLimitation
        let id = "recovery.\(muscle.rawValue).movementLimitation"
        value.constraintFactIDs.append(id)
        facts.append(
          Self.fact(
            id: id, value: response.hasMovementLimitation == true ? 1 : 0,
            date: response.recordedAt, recordID: response.id))
      }
      muscles[muscle] = value
    }
  }
  static func fact(id: String, value: Double?, date: Date, recordID: UUID) -> MetricFact {
    .init(
      id: id, metric: id, value: value, unit: .none,
      window: .init(start: date, end: date), sources: [.manual],
      dependencies: [.init(kind: .manualRecord, id: recordID.uuidString)])
  }
}
