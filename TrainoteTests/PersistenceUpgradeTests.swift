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
