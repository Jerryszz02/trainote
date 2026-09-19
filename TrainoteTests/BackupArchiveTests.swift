import SwiftData
import XCTest

@testable import Trainote

@MainActor
final class BackupArchiveTests: XCTestCase {
  private func container() throws -> ModelContainer {
    try PersistenceController.makeContainer(inMemory: true)
  }

  func testRoundTripIncludesAllElevenEntityTypesAndRelationships() throws {
    let source = try container()
    let context = ModelContext(source)
    let set = StrengthSet(orderIndex: 0, weightKilograms: 60, repetitions: 8, isCompleted: true)
    let cardio = CardioEntry(durationSeconds: 300, distanceKilometers: 2, calories: 100)
    let exercise = WorkoutExercise(
      id: UUID(), sourceExerciseID: "run", nameEnSnapshot: "Run", nameZhSnapshot: "跑步",
      orderIndex: 0, trackingMode: .cardio)
    cardio.exercise = exercise
    exercise.cardioEntries = [cardio]
    let workout = Workout(title: "测试训练", exercises: [exercise])
    exercise.workout = workout
    let routine = Routine(name: "计划")
    let routineExercise = RoutineExercise(
      sourceExerciseID: "run", nameEnSnapshot: "Run", nameZhSnapshot: "跑步", orderIndex: 0,
      trackingMode: .cardio)
    routineExercise.routine = routine
    routine.exercises = [routineExercise]
    let preset = FoodPreset(
      name: "燕麦", caloriesPerServing: 100, carbohydratesPerServing: 10, proteinPerServing: 3,
      fatPerServing: 2)
    let template = MealTemplate(name: "早餐")
    let item = MealTemplateItem(
      orderIndex: 0, nameSnapshot: "燕麦", servingDescriptionSnapshot: "1份", quantity: 1,
      caloriesPerServing: 100, carbohydratesPerServing: 10, proteinPerServing: 3, fatPerServing: 2)
    item.template = template
    template.items = [item]
    let log = FoodLogEntry(
      loggedAt: .now, mealType: .breakfast, name: "燕麦", servingDescription: "1份", quantity: 1,
      calories: 100, carbohydrates: 10, protein: 3, fat: 2)
    let goal = NutritionGoal(calories: 2000, carbohydrates: 200, protein: 100, fat: 60)
    context.insert(workout)
    context.insert(routine)
    context.insert(preset)
    context.insert(template)
    context.insert(log)
    context.insert(goal)
    set.exercise = exercise
    exercise.strengthSets = [set]
    try context.save()
    let data = try BackupArchiveService.export(context: context)
    let decoded = try BackupArchiveService.decode(data)
    XCTAssertEqual(decoded.counts.total, 11)
    let destination = try container()
    let result = try BackupArchiveService.importData(data, into: destination)
    XCTAssertEqual(result.inserted, 11)
    let repeated = try BackupArchiveService.importData(data, into: destination)
    XCTAssertEqual(repeated.inserted, 0)
    XCTAssertEqual(repeated.skipped, 11)
    let restored = ModelContext(destination)
    XCTAssertEqual(try restored.fetchCount(FetchDescriptor<Workout>()), 1)
    XCTAssertEqual(try restored.fetchCount(FetchDescriptor<StrengthSet>()), 1)
    XCTAssertEqual(try restored.fetchCount(FetchDescriptor<CardioEntry>()), 1)
    XCTAssertEqual(try restored.fetchCount(FetchDescriptor<RoutineExercise>()), 1)
    XCTAssertEqual(try restored.fetchCount(FetchDescriptor<MealTemplateItem>()), 1)
  }

  func testImportIsIdempotentAndInvalidArchiveDoesNotMutateData() throws {
    let source = try container()
    let context = ModelContext(source)
    context.insert(
      FoodPreset(
        name: "苹果", caloriesPerServing: 50, carbohydratesPerServing: 12, proteinPerServing: 0,
        fatPerServing: 0))
    let data = try BackupArchiveService.export(context: context)
    let destination = try container()
    let first = try BackupArchiveService.importData(data, into: destination)
    XCTAssertEqual(first.inserted, 1)
    let second = try BackupArchiveService.importData(data, into: destination)
    XCTAssertEqual(second.inserted, 0)
    XCTAssertEqual(second.skipped, 1)
    var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    object["schemaVersion"] = 99
    let bad = try JSONSerialization.data(withJSONObject: object)
    XCTAssertThrowsError(try BackupArchiveService.importData(bad, into: destination))
    XCTAssertEqual(try ModelContext(destination).fetchCount(FetchDescriptor<FoodPreset>()), 1)
    object["schemaVersion"] = 1
    var presets = object["foodPresets"] as! [[String: Any]]
    presets[0]["caloriesPerServing"] = -1
    object["foodPresets"] = presets
    let invalidValues = try JSONSerialization.data(withJSONObject: object)
    XCTAssertThrowsError(try BackupArchiveService.importData(invalidValues, into: destination))
    XCTAssertEqual(try ModelContext(destination).fetchCount(FetchDescriptor<FoodPreset>()), 1)
  }

  func testDuplicateIDsChildCollisionAndMultipleActiveAreRejected() throws {
    let id = UUID()
    let duplicate = BackupArchive(
      schemaVersion: 1, createdAt: .now,
      workouts: [
        WorkoutDTO(
          id: id, title: "a", startedAt: .now, endedAt: nil, statusRaw: "completed", notes: "",
          routineNameSnapshot: nil, restEndsAt: nil, exercises: []),
        WorkoutDTO(
          id: id, title: "b", startedAt: .now, endedAt: nil, statusRaw: "completed", notes: "",
          routineNameSnapshot: nil, restEndsAt: nil, exercises: []),
      ], routines: [], foodPresets: [], mealTemplates: [], foodLogs: [], nutritionGoals: [])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    XCTAssertThrowsError(try BackupArchiveService.decode(try encoder.encode(duplicate)))
    let active = WorkoutDTO(
      id: UUID(), title: "a", startedAt: .now, endedAt: nil, statusRaw: "inProgress", notes: "",
      routineNameSnapshot: nil, restEndsAt: nil, exercises: [])
    let multi = BackupArchive(
      schemaVersion: 1, createdAt: .now,
      workouts: [
        active,
        WorkoutDTO(
          id: UUID(), title: "b", startedAt: .now, endedAt: nil, statusRaw: "inProgress", notes: "",
          routineNameSnapshot: nil, restEndsAt: nil, exercises: []),
      ], routines: [], foodPresets: [], mealTemplates: [], foodLogs: [], nutritionGoals: [])
    XCTAssertThrowsError(try BackupArchiveService.decode(try encoder.encode(multi)))
  }

  func testChildIDCollisionAndActiveConflictLeaveDestinationUnchanged() throws {
    let destination = try container()
    let context = ModelContext(destination)
    let existing = Workout(title: "已有训练")
    let sharedID = UUID()
    let exercise = WorkoutExercise(
      id: sharedID, sourceExerciseID: "a", nameEnSnapshot: "A", nameZhSnapshot: "动作", orderIndex: 0,
      trackingMode: .strength)
    existing.exercises = [exercise]
    context.insert(existing)
    try context.save()
    let source = try container()
    let incomingContext = ModelContext(source)
    incomingContext.insert(
      FoodPreset(
        id: sharedID, name: "冲突食物", caloriesPerServing: 100, carbohydratesPerServing: 10,
        proteinPerServing: 1, fatPerServing: 1))
    let collision = try BackupArchiveService.export(context: incomingContext)
    XCTAssertThrowsError(try BackupArchiveService.importData(collision, into: destination))
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodPreset>()), 0)
    incomingContext.insert(Workout(title: "另一个进行中训练"))
    let active = try BackupArchiveService.export(context: incomingContext)
    XCTAssertThrowsError(try BackupArchiveService.importData(active, into: destination)) { error in
      XCTAssertEqual(error as? BackupArchiveError, .activeWorkoutConflict)
    }
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workout>()), 1)
  }
}
