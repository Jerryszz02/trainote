import Foundation
import SwiftData
import XCTest

@testable import Trainote

@MainActor
final class PersistenceUpgradeTests: XCTestCase {
  func testVersionOneDiskStorePreservesHistoryAndAddsDefaults() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("migration.store")
    let workoutID = UUID()
    let foodID = UUID()
    try autoreleasepool {
      let schema = Schema(LegacyStore.modelTypes)
      let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
      let container = try ModelContainer(for: schema, configurations: [config])
      let context = ModelContext(container)
      let workout = LegacyStore.Workout(id: workoutID, title: "升级前训练")
      let exercise = LegacyStore.WorkoutExercise(
        sourceExerciseID: "0025", nameEnSnapshot: "bench press", nameZhSnapshot: "卧推",
        orderIndex: 0, trackingMode: .strength)
      let set = LegacyStore.StrengthSet(
        orderIndex: 0, weightKilograms: 60, repetitions: 8, isCompleted: true)
      set.exercise = exercise
      exercise.strengthSets = [set]
      exercise.workout = workout
      workout.exercises = [exercise]
      context.insert(workout)
      context.insert(
        LegacyStore.FoodLogEntry(
          id: foodID, loggedAt: .now, mealType: .lunch, name: "原有午餐", servingDescription: "1 份",
          quantity: 1, calories: 600, carbohydrates: 60, protein: 30, fat: 15))
      try context.save()
    }
    try autoreleasepool {
      let upgraded = try PersistenceController.makeContainer(storeURL: url)
      let context = ModelContext(upgraded)
      let workout = try XCTUnwrap(context.fetch(FetchDescriptor<Workout>()).first)
      XCTAssertEqual(workout.id, workoutID)
      XCTAssertNil(workout.restEndsAt)
      XCTAssertNil(workout.exercises.first?.strengthSets.first?.rir)
      XCTAssertEqual(workout.exercises.first?.strengthSets.first?.setRole, .unknown)
      XCTAssertEqual(workout.exercises.first?.trackingMode, .strength)
      XCTAssertEqual(workout.exercises.first?.strengthSets.first?.durationSeconds, 0)
      XCTAssertEqual(workout.exercises.first?.strengthSets.first?.weightKilograms, 60)
      XCTAssertEqual(workout.exercises.first?.strengthSets.first?.isCompleted, true)
      XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntry>()).first?.id, foodID)
      workout.restEndsAt = Date.now.addingTimeInterval(90)
      try context.save()
      let reopened = try PersistenceController.makeContainer(storeURL: url)
      XCTAssertNotNil(
        try ModelContext(reopened).fetch(FetchDescriptor<Workout>()).first?.restEndsAt)
    }
  }

  func testFrozenVersionOneOneDiskStoreMigratesToOneTwo() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("migration-1-1.store")
    let workoutID = AnalysisFixtures.id(301)
    let setID = AnalysisFixtures.id(302)
    let date = AnalysisFixtures.asOf
    try autoreleasepool {
      let schema = Schema(VersionOneOneStore.modelTypes, version: Schema.Version(1, 1, 0))
      let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
      let container = try ModelContainer(for: schema, configurations: [configuration])
      let context = ModelContext(container)
      let workout = VersionOneOneStore.Workout(id: workoutID, title: "1.1 合成训练", startedAt: date)
      workout.restEndsAt = date.addingTimeInterval(90)
      let exercise = VersionOneOneStore.WorkoutExercise(sourceExerciseID: "0025",
        nameEnSnapshot: "Bench", nameZhSnapshot: "卧推", orderIndex: 0, trackingMode: .duration)
      let set = VersionOneOneStore.StrengthSet(id: setID, orderIndex: 0, repetitions: 0, isCompleted: true)
      set.durationSeconds = 45
      set.exercise = exercise
      exercise.strengthSets = [set]
      exercise.workout = workout
      workout.exercises = [exercise]
      context.insert(workout)
      context.insert(VersionOneOneStore.NutritionGoal(calories: 2100, carbohydrates: 250, protein: 130, fat: 60, updatedAt: date))
      try context.save()
    }
    try autoreleasepool {
      let container = try PersistenceController.makeContainer(storeURL: url)
      let context = ModelContext(container)
      let workout = try XCTUnwrap(context.fetch(FetchDescriptor<Workout>()).first)
      let set = try XCTUnwrap(workout.exercises.first?.strengthSets.first)
      XCTAssertEqual(workout.id, workoutID)
      XCTAssertEqual(workout.restEndsAt, date.addingTimeInterval(90))
      XCTAssertEqual(set.id, setID)
      XCTAssertEqual(set.durationSeconds, 45)
      XCTAssertNil(set.rir)
      XCTAssertEqual(set.setRole, .unknown)
      XCTAssertEqual(try context.fetch(FetchDescriptor<NutritionGoal>()).first?.calories, 2100)
      XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyProfile>()), 0)
      XCTAssertEqual(try context.fetchCount(FetchDescriptor<AnalysisPreferences>()), 0)
      context.insert(BodyWeightEntry(value: .init(id: AnalysisFixtures.id(303), measuredAt: date,
        kilograms: 70, timeZoneIdentifier: "UTC", createdAt: date, updatedAt: date)))
      set.rir = 2
      set.setRole = .working
      try context.save()
    }
    let reopened = try PersistenceController.makeContainer(storeURL: url)
    let context = ModelContext(reopened)
    XCTAssertEqual(try context.fetch(FetchDescriptor<StrengthSet>()).first?.rir, 2)
    XCTAssertEqual(try context.fetch(FetchDescriptor<BodyWeightEntry>()).first?.kilograms, 70)
  }

  func testReadOnlyStoreReportsSaveFailure() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("readonly.store")
    try autoreleasepool {
      let initial = try PersistenceController.makeContainer(storeURL: url)
      try initial.mainContext.save()
    }
    try autoreleasepool {
      let container = try PersistenceController.makeContainer(storeURL: url, allowsSave: false)
      let context = ModelContext(container)
      context.insert(NutritionGoal(calories: 2000, carbohydrates: 200, protein: 100, fat: 60))
      XCTAssertThrowsError(try context.save())
    }
  }
}
