import Foundation

enum RoutineFactory {
  static func workout(from routine: Routine?, startedAt: Date = .now) -> Workout {
    guard let routine else {
      return Workout(title: "自由训练", startedAt: startedAt)
    }

    let workout = Workout(
      title: routine.name,
      startedAt: startedAt,
      routineNameSnapshot: routine.name
    )

    for item in routine.sortedExercises {
      let exercise = WorkoutExercise(
        sourceExerciseID: item.sourceExerciseID,
        nameEnSnapshot: item.nameEnSnapshot,
        nameZhSnapshot: item.nameZhSnapshot,
        orderIndex: item.orderIndex,
        trackingMode: item.trackingMode
      )
      exercise.workout = workout

      switch item.trackingMode {
      case .strength, .repetitions, .duration:
        for index in 0..<min(max(item.defaultSetCount, 1), 100) {
          let strengthSet = StrengthSet(
            orderIndex: index,
            weightKilograms: max(item.defaultWeightKilograms, 0),
            repetitions: max(item.defaultRepetitions, 1),
            durationSeconds: max(item.defaultDurationSeconds, 0)
          )
          strengthSet.exercise = exercise
          exercise.strengthSets.append(strengthSet)
        }
      case .cardio:
        // Planned cardio is a target, not a result of the new session.
        exercise.notes =
          "模板目标：\(item.defaultDurationSeconds / 60) 分钟，\(item.defaultDistanceKilometers.formatted()) km"
        let cardio = CardioEntry()
        cardio.exercise = exercise
        exercise.cardioEntries.append(cardio)
      }

      workout.exercises.append(exercise)
    }

    return workout
  }

  static func workoutExercise(
    from item: ExerciseCatalogItem,
    orderIndex: Int
  ) -> WorkoutExercise {
    let mode = item.defaultTrackingMode
    let exercise = WorkoutExercise(
      sourceExerciseID: item.id,
      nameEnSnapshot: item.nameEn,
      nameZhSnapshot: item.displayName,
      orderIndex: orderIndex,
      trackingMode: mode
    )
    if mode.usesSets {
      let strengthSet = StrengthSet(orderIndex: 0)
      strengthSet.exercise = exercise
      exercise.strengthSets.append(strengthSet)
    } else {
      let cardio = CardioEntry()
      cardio.exercise = exercise
      exercise.cardioEntries.append(cardio)
    }
    return exercise
  }

  static func routineExercise(
    from item: ExerciseCatalogItem,
    orderIndex: Int
  ) -> RoutineExercise {
    RoutineExercise(
      sourceExerciseID: item.id,
      nameEnSnapshot: item.nameEn,
      nameZhSnapshot: item.displayName,
      orderIndex: orderIndex,
      trackingMode: item.defaultTrackingMode
    )
  }
}
