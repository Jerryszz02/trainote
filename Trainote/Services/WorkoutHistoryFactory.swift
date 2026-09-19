import Foundation
import SwiftData

enum WorkoutHistoryFactory {
  static func copy(
    of source: Workout, startedAt: Date, status: WorkoutStatus, preserveCompletion: Bool = false
  ) -> Workout {
    let copy = Workout(
      title: source.title, startedAt: startedAt, status: status, notes: source.notes,
      routineNameSnapshot: source.routineNameSnapshot)
    copy.endedAt = preserveCompletion ? source.endedAt : nil
    copy.exercises = source.sortedExercises.map { old in
      let exercise = WorkoutExercise(
        sourceExerciseID: old.sourceExerciseID, nameEnSnapshot: old.nameEnSnapshot,
        nameZhSnapshot: old.nameZhSnapshot, orderIndex: old.orderIndex,
        trackingMode: old.trackingMode, notes: old.notes)
      exercise.workout = copy
      exercise.strengthSets = old.sortedStrengthSets.map { value in
        let set = StrengthSet(
          orderIndex: value.orderIndex, weightKilograms: value.weightKilograms,
          repetitions: value.repetitions, durationSeconds: value.durationSeconds,
          isCompleted: preserveCompletion && value.isCompleted)
        set.exercise = exercise
        return set
      }
      exercise.cardioEntries = old.cardioEntries.map { value in
        let cardio = CardioEntry(
          durationSeconds: preserveCompletion ? value.durationSeconds : 0,
          distanceKilometers: preserveCompletion ? value.distanceKilometers : 0,
          calories: preserveCompletion ? value.calories : 0)
        cardio.exercise = exercise
        return cardio
      }
      return exercise
    }
    return copy
  }

  static func apply(_ draft: Workout, to original: Workout, context: ModelContext) throws {
    let replacement = copy(
      of: draft, startedAt: draft.startedAt, status: .completed, preserveCompletion: true)
    original.title = draft.title.trimmed
    original.notes = draft.notes
    original.startedAt = draft.startedAt
    original.endedAt = draft.endedAt
    let removed = original.exercises
    original.exercises = replacement.exercises
    original.exercises.forEach { $0.workout = original }
    removed.forEach { context.delete($0) }
    do { try context.save() } catch {
      context.rollback()
      throw error
    }
  }

  static func routine(from workout: Workout) -> Routine {
    let routine = Routine(name: workout.title, notes: workout.notes)
    routine.exercises = workout.sortedExercises.map { old in
      let first = old.sortedStrengthSets.first
      let item = RoutineExercise(
        sourceExerciseID: old.sourceExerciseID, nameEnSnapshot: old.nameEnSnapshot,
        nameZhSnapshot: old.nameZhSnapshot, orderIndex: old.orderIndex,
        trackingMode: old.trackingMode, defaultSetCount: max(old.strengthSets.count, 1),
        defaultRepetitions: first?.repetitions ?? 8,
        defaultWeightKilograms: first?.weightKilograms ?? 0,
        defaultDurationSeconds: old.trackingMode == .cardio
          ? (old.cardioEntries.first?.durationSeconds ?? 0) : (first?.durationSeconds ?? 0),
        defaultDistanceKilometers: old.cardioEntries.first?.distanceKilometers ?? 0)
      item.routine = routine
      return item
    }
    return routine
  }
}
