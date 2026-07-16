import SwiftData
import XCTest

@testable import Trainote

final class TrainoteDomainTests: XCTestCase {
  func testRoutineCreatesIndependentWorkoutSnapshot() {
    let routine = Routine(name: "推日")
    let item = RoutineExercise(
      sourceExerciseID: "0025",
      nameEnSnapshot: "barbell bench press",
      nameZhSnapshot: "杠铃卧推",
      orderIndex: 0,
      trackingMode: .strength,
      defaultSetCount: 3,
      defaultRepetitions: 10,
      defaultWeightKilograms: 60
    )
    item.routine = routine
    routine.exercises.append(item)

    let workout = RoutineFactory.workout(from: routine)

    XCTAssertEqual(workout.title, "推日")
    XCTAssertEqual(workout.exercises.count, 1)
    XCTAssertEqual(workout.exercises[0].strengthSets.count, 3)
    XCTAssertEqual(workout.exercises[0].strengthSets[0].weightKilograms, 60)

    routine.name = "已修改"
    item.defaultWeightKilograms = 80

    XCTAssertEqual(workout.title, "推日")
    XCTAssertEqual(workout.exercises[0].strengthSets[0].weightKilograms, 60)
  }

  func testFoodPresetCreatesNutritionSnapshot() {
    let preset = FoodPreset(
      name: "鸡胸肉",
      servingDescription: "100 g",
      caloriesPerServing: 165,
      carbohydratesPerServing: 0,
      proteinPerServing: 31,
      fatPerServing: 3.6
    )

    let entry = FoodLogFactory.entry(
      from: preset,
      quantity: 1.5,
      mealType: .lunch,
      loggedAt: .now
    )

    XCTAssertEqual(entry.calories, 247.5, accuracy: 0.001)
    XCTAssertEqual(entry.protein, 46.5, accuracy: 0.001)

    preset.proteinPerServing = 99
    XCTAssertEqual(entry.protein, 46.5, accuracy: 0.001)
  }

  func testMealTemplateExpandsIntoIndependentFoodLogs() {
    let template = MealTemplate(name: "训练后餐")
    let chicken = MealTemplateItem(
      orderIndex: 0,
      nameSnapshot: "鸡胸肉",
      servingDescriptionSnapshot: "100 g",
      quantity: 1.5,
      caloriesPerServing: 165,
      carbohydratesPerServing: 0,
      proteinPerServing: 31,
      fatPerServing: 3.6
    )
    let rice = MealTemplateItem(
      orderIndex: 1,
      nameSnapshot: "米饭",
      servingDescriptionSnapshot: "1 碗",
      quantity: 2,
      caloriesPerServing: 200,
      carbohydratesPerServing: 45,
      proteinPerServing: 4,
      fatPerServing: 0.5
    )
    chicken.template = template
    rice.template = template
    template.items = [chicken, rice]

    let entries = FoodLogFactory.entries(
      from: template,
      mealType: .dinner,
      loggedAt: .now
    )

    XCTAssertEqual(entries.count, 2)
    XCTAssertEqual(entries[0].protein, 46.5, accuracy: 0.001)
    XCTAssertEqual(entries[1].carbohydrates, 90, accuracy: 0.001)
    XCTAssertTrue(entries.allSatisfy { $0.mealType == .dinner })

    chicken.proteinPerServing = 99
    XCTAssertEqual(entries[0].protein, 46.5, accuracy: 0.001)
  }

  func testTemplateValidationRejectsNegativeOrZeroValues() {
    let routineItem = RoutineExercise(
      sourceExerciseID: "0025",
      nameEnSnapshot: "barbell bench press",
      nameZhSnapshot: "杠铃卧推",
      orderIndex: 0,
      trackingMode: .strength,
      defaultSetCount: 3,
      defaultRepetitions: 8,
      defaultWeightKilograms: -1
    )
    XCTAssertFalse(routineItem.hasValidDefaults)

    let template = MealTemplate(name: "早餐")
    let item = MealTemplateItem(
      orderIndex: 0,
      nameSnapshot: "燕麦",
      servingDescriptionSnapshot: "1 份",
      quantity: 0,
      caloriesPerServing: 380,
      carbohydratesPerServing: 68,
      proteinPerServing: 13,
      fatPerServing: 7
    )
    item.template = template
    template.items = [item]
    XCTAssertFalse(template.isValid)
  }

  func testDailyNutritionSummaryPreservesOverage() {
    let entry = FoodLogEntry(
      loggedAt: .now,
      mealType: .dinner,
      name: "晚餐",
      servingDescription: "1 份",
      quantity: 1,
      calories: 2_200,
      carbohydrates: 260,
      protein: 140,
      fat: 70
    )
    let goal = NutritionGoal(calories: 2_000, carbohydrates: 250, protein: 150, fat: 65)

    let summary = DailyNutritionSummary(entries: [entry], goal: goal)

    XCTAssertEqual(summary.remaining(for: .calories), -200)
    XCTAssertEqual(summary.progress(for: .calories), 1)
    XCTAssertEqual(summary.remaining(for: .protein), 10)
  }

  func testWorkoutCompletionRequiresValidResult() {
    let workout = Workout(title: "测试")
    let exercise = WorkoutExercise(
      sourceExerciseID: "0025",
      nameEnSnapshot: "barbell bench press",
      nameZhSnapshot: "杠铃卧推",
      orderIndex: 0,
      trackingMode: .strength
    )
    let strengthSet = StrengthSet(orderIndex: 0, weightKilograms: 60, repetitions: 8)
    strengthSet.exercise = exercise
    exercise.strengthSets.append(strengthSet)
    exercise.workout = workout
    workout.exercises.append(exercise)

    XCTAssertFalse(workout.hasValidResult)
    strengthSet.isCompleted = true
    XCTAssertTrue(workout.hasValidResult)
  }
}

@MainActor
final class ExerciseCatalogTests: XCTestCase {
  func testCatalogFixesTrackingModeByExerciseCategory() {
    let strength = makeItem(id: "0032", nameEn: "barbell deadlift", bodyPart: "upper legs")
    let cardio = makeItem(id: "0685", nameEn: "run", bodyPart: "cardio")

    XCTAssertEqual(strength.defaultTrackingMode, .strength)
    XCTAssertEqual(cardio.defaultTrackingMode, .cardio)
  }

  func testCatalogSearchSupportsChineseEnglishAndFilters() {
    let item = ExerciseCatalogItem(
      id: "0025",
      nameEn: "barbell bench press",
      nameZh: "杠铃卧推",
      bodyPart: "chest",
      equipment: "barbell",
      target: "pectorals",
      muscleGroup: "triceps",
      secondaryMuscles: ["shoulders"],
      instructionsEn: "Press the bar.",
      instructionsZh: "推起杠铃。",
      stepsEn: ["Press."],
      stepsZh: ["推起。"]
    )
    let catalog = ExerciseCatalog(items: [item])

    XCTAssertEqual(catalog.filtered(query: "卧推").map(\.id), ["0025"])
    XCTAssertEqual(catalog.filtered(query: "bench").map(\.id), ["0025"])
    XCTAssertEqual(catalog.filtered(query: "", bodyPart: "chest").map(\.id), ["0025"])
    XCTAssertEqual(
      catalog.filtered(
        query: "",
        bodyPart: "chest",
        equipment: "barbell",
        muscleGroup: "triceps"
      ).map(\.id),
      ["0025"]
    )
    XCTAssertTrue(catalog.filtered(query: "", muscleGroup: "biceps").isEmpty)
    XCTAssertTrue(catalog.filtered(query: "", equipment: "dumbbell").isEmpty)
  }

  func testBundledCatalogHasExpectedContentAndNoMediaKeys() throws {
    guard let url = Bundle.main.url(forResource: "ExerciseCatalog", withExtension: "json") else {
      return XCTFail("缺少 ExerciseCatalog.json")
    }
    let data = try Data(contentsOf: url)
    let document = try JSONDecoder().decode(ExerciseCatalogDocument.self, from: data)

    XCTAssertEqual(document.exercises.count, 1_324)
    XCTAssertEqual(Set(document.exercises.map(\.id)).count, 1_324)
    XCTAssertTrue(document.exercises.allSatisfy { !$0.nameZh.trimmed.isEmpty })

    let text = String(decoding: data, as: UTF8.self)
    for forbiddenKey in ["\"image\"", "\"gif_url\"", "\"media_id\""] {
      XCTAssertFalse(text.contains(forbiddenKey), "资源不应包含 \(forbiddenKey)")
    }
  }

  private func makeItem(
    id: String,
    nameEn: String,
    bodyPart: String
  ) -> ExerciseCatalogItem {
    ExerciseCatalogItem(
      id: id,
      nameEn: nameEn,
      nameZh: nameEn,
      bodyPart: bodyPart,
      equipment: "body weight",
      target: "target",
      muscleGroup: "muscle",
      secondaryMuscles: [],
      instructionsEn: "Instruction.",
      instructionsZh: "说明。",
      stepsEn: ["Step."],
      stepsZh: ["步骤。"]
    )
  }
}

@MainActor
final class PersistenceTests: XCTestCase {
  func testCascadeDeleteRemovesWorkoutChildren() throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let workout = Workout(title: "测试")
    let exercise = WorkoutExercise(
      sourceExerciseID: "0025",
      nameEnSnapshot: "barbell bench press",
      nameZhSnapshot: "杠铃卧推",
      orderIndex: 0,
      trackingMode: .strength
    )
    let strengthSet = StrengthSet(orderIndex: 0)
    strengthSet.exercise = exercise
    exercise.strengthSets.append(strengthSet)
    exercise.workout = workout
    workout.exercises.append(exercise)
    context.insert(workout)
    try context.save()

    context.delete(workout)
    try context.save()

    XCTAssertTrue(try context.fetch(FetchDescriptor<Workout>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutExercise>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<StrengthSet>()).isEmpty)
  }

  func testDeletingPresetKeepsHistoricalFoodLog() throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let preset = FoodPreset(
      name: "燕麦",
      caloriesPerServing: 380,
      carbohydratesPerServing: 68,
      proteinPerServing: 13,
      fatPerServing: 7
    )
    let entry = FoodLogFactory.entry(
      from: preset, quantity: 1, mealType: .breakfast, loggedAt: .now)
    context.insert(preset)
    context.insert(entry)
    try context.save()

    context.delete(preset)
    try context.save()

    XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntry>()).count, 1)
  }

  func testInProgressWorkoutCanBeRecoveredFromANewContext() throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let writeContext = ModelContext(container)
    writeContext.insert(Workout(title: "恢复测试"))
    try writeContext.save()

    let readContext = ModelContext(container)
    let recovered = try XCTUnwrap(readContext.fetch(FetchDescriptor<Workout>()).first)

    XCTAssertEqual(recovered.title, "恢复测试")
    XCTAssertEqual(recovered.status, .inProgress)
  }

  func testRoutineAndMealTemplateCascadeDeleteTheirChildren() throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let context = ModelContext(container)

    let routine = Routine(name: "上肢")
    let routineItem = RoutineExercise(
      sourceExerciseID: "0025",
      nameEnSnapshot: "barbell bench press",
      nameZhSnapshot: "杠铃卧推",
      orderIndex: 0,
      trackingMode: .strength
    )
    routineItem.routine = routine
    routine.exercises = [routineItem]

    let template = MealTemplate(name: "早餐")
    let mealItem = MealTemplateItem(
      orderIndex: 0,
      nameSnapshot: "燕麦",
      servingDescriptionSnapshot: "1 份",
      quantity: 1,
      caloriesPerServing: 380,
      carbohydratesPerServing: 68,
      proteinPerServing: 13,
      fatPerServing: 7
    )
    mealItem.template = template
    template.items = [mealItem]
    context.insert(routine)
    context.insert(template)
    try context.save()

    context.delete(routine)
    context.delete(template)
    try context.save()

    XCTAssertTrue(try context.fetch(FetchDescriptor<RoutineExercise>()).isEmpty)
    XCTAssertTrue(try context.fetch(FetchDescriptor<MealTemplateItem>()).isEmpty)
  }
}
