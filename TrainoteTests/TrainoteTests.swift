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
    XCTAssertEqual(summary.displayedRemaining(for: .calories), -200)
    let fractional = DailyNutritionSummary(
      entries: [FoodLogEntry(loggedAt: .now, mealType: .dinner, name: "测试",
        servingDescription: "1 份", quantity: 1, calories: 1_000.6,
        carbohydrates: 0, protein: 0, fat: 0)],
      historicalTargets: .init(calories: 1_962.3, carbohydrates: 0, protein: 0, fat: 0))
    XCTAssertEqual(fractional.displayedRemaining(for: .calories), 961)
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

  func testIndexPreservesLegacySearchOrderAndCombinedFilters() async throws {
    let catalog = ExerciseCatalog()
    XCTAssertTrue(catalog.isLoading)
    XCTAssertTrue(catalog.items.isEmpty)
    await catalog.load()
    XCTAssertNil(catalog.errorMessage)
    XCTAssertFalse(catalog.isLoading)
    XCTAssertEqual(catalog.items.count, 1324)
    for query in ["", "  ", "bench", "  BÉNCH  ", "卧推", "dumbbell", "triceps", "不存在"] {
      for bodyPart in [nil, "chest", "back"] as [String?] {
        for equipment in [nil, "barbell", "dumbbell"] as [String?] {
          let normalized = query.trimmed.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
          let expected = catalog.items.filter {
            (bodyPart == nil || $0.bodyPart == bodyPart)
              && (equipment == nil || $0.equipment == equipment)
              && (normalized.isEmpty || $0.searchText.localizedStandardContains(normalized))
          }
          XCTAssertEqual(catalog.filtered(query: query, bodyPart: bodyPart, equipment: equipment)
            .map(\.id), expected.map(\.id), "query=\(query)")
        }
      }
    }
    XCTAssertEqual(catalog.bodyParts, Array(Set(catalog.items.map(\.bodyPart))).sorted())
    XCTAssertEqual(catalog.equipmentTypes, Array(Set(catalog.items.map(\.equipment))).sorted())
    XCTAssertEqual(catalog.muscleGroups, Array(Set(catalog.items.flatMap {
      [$0.target, $0.muscleGroup] + $0.secondaryMuscles
    })).sorted())
  }

  func testChineseAliasesMatchClassificationEvenWhenNameDoesNotContainAlias() {
    let item = makeItem(id: "one", nameEn: "push up", bodyPart: "chest")
    let catalog = ExerciseCatalog(items: [item])
    XCTAssertEqual(catalog.filtered(query: "自重").map(\.id), ["one"])
    XCTAssertEqual(catalog.filtered(query: "胸部").map(\.id), ["one"])
    XCTAssertTrue(catalog.filtered(query: "哑铃").isEmpty)
    XCTAssertTrue(catalog.filtered(query: "自重", bodyPart: "back").isEmpty)
  }

  func testConsecutiveQueriesAndClearNeverReuseOldResults() {
    let catalog = ExerciseCatalog(items: [
      makeItem(id: "bench", nameEn: "bench press", bodyPart: "chest"),
      makeItem(id: "run", nameEn: "run", bodyPart: "cardio"),
    ])
    for _ in 0..<30 {
      XCTAssertEqual(catalog.filtered(query: "bench").map(\.id), ["bench"])
      XCTAssertEqual(catalog.filtered(query: "run").map(\.id), ["run"])
      XCTAssertTrue(catalog.filtered(query: "run", bodyPart: "chest").isEmpty)
      XCTAssertEqual(catalog.filtered(query: "").map(\.id), ["bench", "run"])
    }
  }

  func testLoadingIsOffMainAndSharedAcrossCancelledAndActiveConsumers() async {
    let started = expectation(description: "Background preparation started")
    let probe = CatalogLoadProbe()
    let prepared = ExerciseCatalogIndex(items: [makeItem(id: "one", nameEn: "run", bodyPart: "cardio")])
    let catalog = ExerciseCatalog(loader: {
      XCTAssertFalse(Thread.isMainThread, "Resource preparation must not occupy the main thread")
      probe.recordLoad()
      started.fulfill()
      _ = probe.gate.wait(timeout: .now() + 5)
      return prepared
    })
    let first = Task { await catalog.load() }
    let second = Task { await catalog.load() }
    await fulfillment(of: [started], timeout: 3)
    XCTAssertTrue(catalog.isLoading)
    XCTAssertTrue(catalog.items.isEmpty)
    first.cancel()
    probe.gate.signal()
    await first.value
    await second.value
    XCTAssertEqual(probe.count, 1)
    XCTAssertFalse(catalog.isLoading)
    XCTAssertEqual(catalog.items.map(\.id), ["one"])
    await catalog.load()
    XCTAssertEqual(probe.count, 1, "A loaded immutable resource should be reused")
  }

  func testLoadFailureCanRetryWithoutPublishingPartialContent() async {
    let probe = CatalogLoadProbe()
    let prepared = ExerciseCatalogIndex(items: [makeItem(id: "one", nameEn: "run", bodyPart: "cardio")])
    let catalog = ExerciseCatalog(loader: {
      if probe.recordLoad() == 1 { throw CatalogError.resourceMissing }
      return prepared
    })
    await catalog.load()
    XCTAssertNotNil(catalog.errorMessage)
    XCTAssertFalse(catalog.isLoading)
    XCTAssertTrue(catalog.items.isEmpty)
    XCTAssertTrue(catalog.bodyParts.isEmpty)
    await catalog.load()
    XCTAssertNil(catalog.errorMessage)
    XCTAssertFalse(catalog.isLoading)
    XCTAssertEqual(catalog.items.map(\.id), ["one"])
    XCTAssertEqual(probe.count, 2)
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

// Only the test loader uses this lock-protected counter across executors.
private final class CatalogLoadProbe: @unchecked Sendable {
  let gate = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var loads = 0
  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return loads
  }
  @discardableResult func recordLoad() -> Int {
    lock.lock()
    defer { lock.unlock() }
    loads += 1
    return loads
  }
}
