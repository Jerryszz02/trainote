import Foundation

/// Calibration uses subsequent comparable performance; soreness is not a fitted outcome.
/// No learned parameters are stored. Every invocation replays the current manual snapshot.
enum RecoveryCalibration {
  struct Observation: Equatable {
    var workoutID: UUID
    var date: Date
    var observedPerformance: Double
    var priorLoads: [RecoveryLoadSession]
    var dependencies: [SourceDependency]
  }
  struct Result {
    var tauHours: Double = RecoveryParameters.tauHours
    var isAdopted = false
    var evaluatedAt: Date?
    var trainingCount = 0
    var holdoutCount = 0
    var baselineError: Double?
    var candidateError: Double?
    var windowStart: Date
    var dependencies: [SourceDependency] = []
    var sources: [DataSource] = [.manual]
  }

  static func evaluate(
    input: AnalysisInput, sessions: [RecoveryLoadSession],
    mapping: ExerciseMuscleMap, resetAt: Date?, unallocated: [RecoveryLoadSession] = []
  ) -> [MuscleID: Result] {
    let observations = observations(
      input: input, sessions: sessions, mapping: mapping, resetAt: resetAt, unallocated: unallocated
    )
    return Dictionary(
      uniqueKeysWithValues: MuscleID.allCases.map { muscle in
        var result = fit(observations[muscle] ?? [], muscle: muscle, asOf: input.asOf)
        // Coverage exclusions are inputs to eligibility and retain their complete lineage.
        result.dependencies = RecoveryEvidence.dependencies(
          result.dependencies + unallocated.flatMap(\.dependencies))
        result.sources = RecoveryEvidence.sortedSources([.manual] + unallocated.flatMap(\.sources))
        result.windowStart = min(
          result.windowStart, unallocated.map(\.endedAt).min() ?? result.windowStart)
        return (muscle, result)
      })
  }

  static func fit(_ observations: [Observation], muscle: MuscleID, asOf: Date) -> Result {
    let ordered = observations.filter { $0.date <= asOf && $0.observedPerformance.isFinite }
      .sorted {
        $0.date == $1.date ? $0.workoutID.uuidString < $1.workoutID.uuidString : $0.date < $1.date
      }
    var result = Result(windowStart: ordered.first?.date ?? asOf)
    guard ordered.count >= 10 else { return result }
    // Six fit observations plus four later observations, never the same rows.
    for count in 10...ordered.count {
      let prefix = Array(ordered.prefix(count))
      let date = prefix.last!.date
      if let last = result.evaluatedAt, date.timeIntervalSince(last) < 7 * 86_400 { continue }
      let train = Array(prefix.dropLast(4))
      let holdout = Array(prefix.suffix(4))
      guard let fitEnd = train.last?.date, let validationStart = holdout.first?.date,
        fitEnd < validationStart
      else { continue }
      let low = max(24, result.tauHours * 0.9)
      let high = min(72, result.tauHours * 1.1)
      let candidates = (0...20).map { low + (high - low) * Double($0) / 20 }
      let tau = candidates.min { lhs, rhs in
        let a = error(train, tau: lhs, muscle: muscle)
        let b = error(train, tau: rhs, muscle: muscle)
        return a == b ? abs(lhs - result.tauHours) < abs(rhs - result.tauHours) : a < b
      }!
      let baseline = error(holdout, tau: RecoveryParameters.tauHours, muscle: muscle)
      let current = error(holdout, tau: result.tauHours, muscle: muscle)
      let candidate = error(holdout, tau: tau, muscle: muscle)
      result.evaluatedAt = date
      result.trainingCount = train.count
      result.holdoutCount = holdout.count
      result.baselineError = baseline
      result.candidateError = candidate
      // Predeclared product gate: >=5% and >=1 squared point better than BOTH priors.
      if candidate <= min(baseline, current) * 0.95 && candidate + 1 < min(baseline, current) {
        result.tauHours = tau
        result.isAdopted = true
      }
      result.dependencies = RecoveryEvidence.dependencies(
        prefix.flatMap {
          $0.dependencies + $0.priorLoads.flatMap(\.dependencies)
        })
    }
    return result
  }

  static func prediction(_ observation: Observation, tau: Double, muscle: MuscleID) -> Double {
    let load = observation.priorLoads.reduce(0.0) {
      $0 + ($1.load[muscle] ?? 0)
        * exp(-observation.date.timeIntervalSince($1.endedAt) / 3600 / tau)
    }
    return RecoveryParameters.score(residualLoad: load)
  }
  private static func error(_ observations: [Observation], tau: Double, muscle: MuscleID) -> Double
  {
    observations.reduce(0) {
      $0 + pow(prediction($1, tau: tau, muscle: muscle) - $1.observedPerformance, 2)
    } / Double(observations.count)
  }

  static func observations(
    input: AnalysisInput, sessions: [RecoveryLoadSession],
    mapping: ExerciseMuscleMap, resetAt: Date?, unallocated: [RecoveryLoadSession] = []
  ) -> [MuscleID: [Observation]] {
    struct Performance {
      var repetitions: Double
      var dependencies: [SourceDependency]
    }
    var history: [String: [Performance]] = [:]
    var result: [MuscleID: [Observation]] = [:]
    let byID = mapping.byID
    let validIDs = Set(sessions.map(\.workoutID))
    for workout in input.workouts.sorted(by: {
      $0.startedAt == $1.startedAt
        ? $0.id.uuidString < $1.id.uuidString : $0.startedAt < $1.startedAt
    }) {
      guard
        !unallocated.contains(where: {
          $0.endedAt <= (workout.endedAt ?? workout.startedAt)
            && workout.startedAt.timeIntervalSince($0.endedAt) <= 28 * 86_400
        }), validIDs.contains(workout.id), let end = workout.endedAt,
        end <= input.asOf, resetAt.map({ workout.startedAt > $0 }) ?? true,
        workout.exercises.allSatisfy({ exercise in
          exercise.sets.allSatisfy { !$0.isCompleted || $0.role == .warmup }
            || byID[exercise.sourceExerciseID]?.status == .mapped
        })
      else { continue }
      let checks = input.checkIns.filter {
        $0.updatedAt <= workout.startedAt
          && workout.startedAt.timeIntervalSince($0.updatedAt) <= 86_400
          && $0.feeling != nil
      }.sorted {
        $0.updatedAt == $1.updatedAt
          ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt < $1.updatedAt
      }
      guard let check = checks.last else { continue }
      var candidates: [MuscleID: [Observation]] = [:]
      for exercise in workout.exercises.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
        guard exercise.trackingMode == TrackingMode.strength.rawValue,
          let entry = byID[exercise.sourceExerciseID], entry.status == .mapped
        else { continue }
        for set in exercise.sets.sorted(by: { $0.orderIndex < $1.orderIndex }) {
          guard set.isCompleted, set.role == .working, let rir = set.rir, (0...4).contains(rir),
            set.weightKilograms > 0, RecoveryCalculator.valid(set, mode: exercise.trackingMode)
          else { continue }
          // Same catalog ID fixes nominal equipment; exact load, row and RIR avoid an e1RM conversion.
          let key =
            "\(exercise.sourceExerciseID)|\(exercise.trackingMode)|\(set.orderIndex)|\(rir)|\(set.weightKilograms)"
          let previous = Array((history[key] ?? []).suffix(3))
          let deps: [SourceDependency] = [workout.id, exercise.id, set.id, check.id].map {
            .init(kind: .manualRecord, id: $0.uuidString)
          }
          defer {
            history[key, default: []].append(
              .init(repetitions: Double(set.repetitions), dependencies: deps))
          }
          guard previous.count == 3 else { continue }
          let reference = previous.map(\.repetitions).sorted()[1]
          let performance = min(100, 100 * Double(set.repetitions) / reference)
          let prior = sessions.filter { session in
            session.endedAt < workout.startedAt
              && workout.startedAt.timeIntervalSince(session.endedAt) <= 28 * 86_400
              && (resetAt.map { session.endedAt > $0 } ?? true)
          }
          for muscle in entry.primary {
            guard
              let response = check.muscleFeedback.first(where: {
                $0.muscleID == muscle && $0.soreness != nil
                  && $0.recordedAt <= workout.startedAt && $0.hasPain == false
                  && $0.hasMovementLimitation == false
              }), prior.contains(where: { $0.load[muscle] != nil })
            else { continue }
            candidates[muscle, default: []].append(
              .init(
                workoutID: workout.id, date: workout.startedAt, observedPerformance: performance,
                priorLoads: prior,
                dependencies: RecoveryEvidence.dependencies(
                  deps + previous.flatMap(\.dependencies)
                    + [.init(kind: .manualRecord, id: response.id.uuidString)])))
          }
        }
      }
      // Multiple sets from one workout are one paired observation, not six samples.
      for muscle in MuscleID.allCases {
        guard let values = candidates[muscle], var combined = values.first else { continue }
        combined.observedPerformance =
          values.map(\.observedPerformance).reduce(0, +) / Double(values.count)
        combined.dependencies = RecoveryEvidence.dependencies(values.flatMap(\.dependencies))
        result[muscle, default: []].append(combined)
      }
    }
    return result
  }
}

/// Only a reset boundary is saved. It contains no derived score or health import.
final class RecoveryCalibrationControl {
  private let defaults: UserDefaults
  private let key = "recovery.calibration.v0.resetAfter"
  init(defaults: UserDefaults = .standard) { self.defaults = defaults }
  var resetAt: Date? {
    guard let seconds = defaults.object(forKey: key) as? Double, seconds.isFinite else {
      return nil
    }
    return Date(timeIntervalSince1970: seconds)
  }
  func reset(at date: Date) { defaults.set(date.timeIntervalSince1970, forKey: key) }
  /// Call when deleting all local records. There is no health-dependent derived cache.
  func clear() { defaults.removeObject(forKey: key) }
}

/// Production adapter reads the latest reset setting, then recomputes a pure result.
struct RecoveryService: RecoveryCalculating {
  let mapping: ExerciseMuscleMap
  let calibration: RecoveryCalibrationControl
  init(bundle: Bundle = .main, calibration: RecoveryCalibrationControl = .init()) throws {
    self.mapping = try .load(bundle: bundle)
    self.calibration = calibration
  }
  func calculate(_ input: AnalysisInput) throws -> RecoveryResult {
    try RecoveryCalculator(mapping: mapping, calibrationResetAt: calibration.resetAt).calculate(
      input)
  }
}
