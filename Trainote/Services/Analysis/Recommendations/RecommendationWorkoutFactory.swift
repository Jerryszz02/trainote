import Foundation

extension RecommendationPlan {
  /// Includes all defaults used to create the workout, so editing the template invalidates adoption.
  static func snapshot(_ routine: Routine) -> Self {
    struct Item: Encodable {
      var id: UUID
      var sourceID: String
      var mode: String
      var sets: Int
      var weight: Double
      var repetitions: Int
      var duration: Int
      var distance: Double
    }
    let items = routine.sortedExercises.map {
      Item(
        id: $0.id, sourceID: $0.sourceExerciseID, mode: $0.trackingModeRaw,
        sets: $0.defaultSetCount, weight: $0.defaultWeightKilograms,
        repetitions: $0.defaultRepetitions, duration: $0.defaultDurationSeconds,
        distance: $0.defaultDistanceKilometers)
    }
    let revision =
      RecommendationIdentity.digest(items)
      + RecommendationIdentity.digest([routine.name, routine.notes])
    return .init(
      id: routine.id, revision: revision,
      exerciseIDs: routine.sortedExercises.map(\.sourceExerciseID))
  }
}

enum RecommendationWorkoutFactory {
  /// Re-evaluate from current records at adoption, then bind the action to its exact template.
  /// Returns a new unsaved snapshot. The existing save/rollback workflow owns persistence.
  static func make(
    routine: Routine, actionID: String, parameters: [String: Double] = [:], startedAt: Date,
    reevaluate: () throws -> TrainingRecommendationEvaluation
  ) throws -> Workout {
    let current = try reevaluate()
    guard let candidate = current.candidates.first(where: { $0.actionID == actionID }),
      let expectedPlan = current.plansByAction[actionID],
      RecommendationPlan.snapshot(routine) == expectedPlan,
      !routine.exercises.isEmpty, routine.exercises.allSatisfy(\.hasValidDefaults),
      [.keepPlan, .reduceSets, .increaseRIR, .swapTrainingDay].contains(candidate.action),
      Set(parameters.keys) == Set(candidate.allowedParameters.map(\.name)),
      candidate.allowedParameters.allSatisfy({ allowed in
        guard let value = parameters[allowed.name] else { return false }
        return value.isFinite && value >= allowed.minimum && value <= allowed.maximum
      })
    else { throw AnalysisFailure.staleSnapshot }
    let workout = RoutineFactory.workout(from: routine, startedAt: startedAt)
    if candidate.action == .reduceSets {
      guard let percent = parameters["retainedSetPercent"], (1...100).contains(percent) else {
        throw AnalysisFailure.invalidInput
      }
      for exercise in workout.exercises where exercise.trackingMode.usesSets {
        let retained = max(
          1, Int((Double(exercise.strengthSets.count) * percent / 100).rounded(.down)))
        exercise.strengthSets = Array(exercise.sortedStrengthSets.prefix(retained))
      }
      workout.notes = "今日建议：工作组保留 \(Int(percent))%。"
    } else if candidate.action == .increaseRIR {
      guard let rir = parameters["minimumRIR"], rir.rounded() == rir, (0...5).contains(rir) else {
        throw AnalysisFailure.invalidInput
      }
      // RIR fields are observed results, never prefill a prescribed target as a measurement.
      workout.notes = "今日建议：每组至少保留 \(Int(rir)) 次余力；完成后再记录实际 RIR。"
    }
    for set in workout.exercises.flatMap(\.strengthSets) {
      set.isCompleted = false
      set.rir = nil
      set.setRole = .working
    }
    return workout
  }
}
