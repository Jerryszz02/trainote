import SwiftData
import XCTest

@testable import Trainote

@MainActor
final class TrainingUpgradeTests: XCTestCase {
  func testRoutineSnapshotPreservesAllTrackingModesAndResetsCompletion() {
    let routine = Routine(name: "混合训练")
    let modes: [TrackingMode] = [.strength, .repetitions, .duration, .cardio]
    routine.exercises = modes.enumerated().map { index, mode in
      let item = RoutineExercise(
        sourceExerciseID: "e\(index)", nameEnSnapshot: "Exercise", nameZhSnapshot: "动作",
        orderIndex: index, trackingMode: mode, defaultSetCount: 1, defaultRepetitions: 12,
        defaultDurationSeconds: 30)
      item.routine = routine
      return item
    }

    let workout = RoutineFactory.workout(from: routine)
    XCTAssertEqual(workout.exercises.map(\.trackingMode), modes)
    XCTAssertEqual(workout.exercises.filter { $0.trackingMode.usesSets }.count, 3)
    XCTAssertEqual(workout.exercises.last?.cardioEntries.count, 1)
    workout.exercises[0].strengthSets[0].isCompleted = true
    let second = RoutineFactory.workout(from: routine)
    XCTAssertFalse(second.exercises[0].strengthSets[0].isCompleted)
  }

  func testDurationAndRepetitionSnapshotsKeepIndependentRows() {
    let routine = Routine(name: "时长")
    let item = RoutineExercise(
      sourceExerciseID: "stretch", nameEnSnapshot: "Stretch", nameZhSnapshot: "拉伸", orderIndex: 0,
      trackingMode: .duration, defaultSetCount: 2, defaultDurationSeconds: 45)
    item.routine = routine
    routine.exercises = [item]
    let workout = RoutineFactory.workout(from: routine)
    XCTAssertEqual(workout.exercises[0].strengthSets.map(\.durationSeconds), [45, 45])
    workout.exercises[0].strengthSets[0].durationSeconds = 90
    XCTAssertEqual(workout.exercises[0].strengthSets[1].durationSeconds, 45)
  }

  func testRepeatedCardioRequiresNewResultAndHistoricalDraftPreservesValues() throws {
    let exercise = WorkoutExercise(
      sourceExerciseID: "run", nameEnSnapshot: "Run", nameZhSnapshot: "跑步", orderIndex: 0,
      trackingMode: .cardio)
    exercise.cardioEntries = [CardioEntry(durationSeconds: 1800, distanceKilometers: 5)]
    let source = Workout(
      title: "跑步", startedAt: .now.addingTimeInterval(-3600), endedAt: .now, status: .completed,
      exercises: [exercise])
    let repeated = WorkoutHistoryFactory.copy(of: source, startedAt: .now, status: .inProgress)
    XCTAssertFalse(repeated.hasValidResult)
    XCTAssertEqual(repeated.exercises[0].cardioEntries[0].durationSeconds, 0)
    let draft = WorkoutHistoryFactory.copy(
      of: source, startedAt: source.startedAt, status: .completed, preserveCompletion: true)
    XCTAssertTrue(draft.hasValidResult)
    draft.exercises[0].cardioEntries[0].durationSeconds = 2400
    XCTAssertEqual(source.exercises[0].cardioEntries[0].durationSeconds, 1800)
    let container = try PersistenceController.makeContainer(inMemory: true)
    let context = ModelContext(container)
    context.insert(source)
    try context.save()
    try WorkoutHistoryFactory.apply(draft, to: source, context: context)
    XCTAssertEqual(source.exercises[0].cardioEntries[0].durationSeconds, 2400)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workout>()), 1)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<CardioEntry>()), 1)
  }

  func testOversizedLegacyTemplateIsBoundedAndCardioTargetsAreNotResults() {
    let routine = Routine(name: "旧模板")
    routine.exercises = [
      RoutineExercise(
        sourceExerciseID: "bench", nameEnSnapshot: "Bench", nameZhSnapshot: "卧推", orderIndex: 0,
        trackingMode: .strength, defaultSetCount: Int.max)
    ]
    let workout = RoutineFactory.workout(from: routine)
    XCTAssertEqual(workout.exercises[0].strengthSets.count, 100)
    routine.exercises = [
      RoutineExercise(
        sourceExerciseID: "run", nameEnSnapshot: "Run", nameZhSnapshot: "跑步", orderIndex: 0,
        trackingMode: .cardio, defaultDurationSeconds: 1800)
    ]
    XCTAssertFalse(RoutineFactory.workout(from: routine).hasValidResult)
  }
  func testSavingCardioAsTemplateUsesActiveModeDespiteHiddenSets() {
    let exercise = WorkoutExercise(
      sourceExerciseID: "run", nameEnSnapshot: "Run", nameZhSnapshot: "跑步", orderIndex: 0,
      trackingMode: .cardio)
    exercise.strengthSets = [StrengthSet(orderIndex: 0, durationSeconds: 45)]
    exercise.cardioEntries = [CardioEntry(durationSeconds: 1800, distanceKilometers: 5)]
    let source = Workout(title: "有氧", exercises: [exercise])
    let template = WorkoutHistoryFactory.routine(from: source)
    XCTAssertEqual(template.exercises[0].defaultDurationSeconds, 1800)
    XCTAssertEqual(template.exercises[0].defaultDistanceKilometers, 5)
  }
}
