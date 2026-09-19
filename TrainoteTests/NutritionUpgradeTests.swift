import SwiftData
import XCTest

@testable import Trainote

final class NutritionUpgradeTests: XCTestCase {
  // MARK: - 份量缩放

  func testQuantityScalingUsesStartingPerUnitDensity() {
    var draft = FoodNutritionDraft(
      name: "鸡胸肉",
      inputMode: .perServing,
      amount: 1,
      perUnit: NutritionValues(calories: 165, carbohydrates: 0, protein: 31, fat: 3.6),
      servingDescription: "1 份"
    )

    XCTAssertEqual(draft.totals.calories, 165, accuracy: 0.001)
    XCTAssertEqual(draft.totals.protein, 31, accuracy: 0.001)

    draft.amount = 1.5
    XCTAssertEqual(draft.totals.calories, 247.5, accuracy: 0.001)
    XCTAssertEqual(draft.totals.protein, 46.5, accuracy: 0.001)

    draft.amount = 3
    XCTAssertEqual(draft.totals.calories, 495, accuracy: 0.001)
  }

  func testManualNutrientCorrectionScalesSubsequentQuantityChange() {
    var draft = FoodNutritionDraft(
      name: "自定义",
      inputMode: .perServing,
      amount: 1,
      perUnit: NutritionValues(calories: 100, carbohydrates: 10, protein: 5, fat: 2),
      servingDescription: "1 份"
    )

    draft.setTotal(.calories, to: 250)
    XCTAssertEqual(draft.totals.calories, 250, accuracy: 0.001)
    XCTAssertEqual(draft.perUnit.calories, 250, accuracy: 0.001)

    draft.amount = 2
    XCTAssertEqual(draft.totals.calories, 500, accuracy: 0.001)
    XCTAssertEqual(draft.totals.carbohydrates, 20, accuracy: 0.001)
  }

  // MARK: - 每 100 克

  func testPer100gPresetCalculation() {
    let preset = FoodPreset(
      name: "鸡胸肉",
      servingDescription: "100 g",
      caloriesPerServing: 165,
      carbohydratesPerServing: 0,
      proteinPerServing: 31,
      fatPerServing: 3.6
    )

    var draft = FoodNutritionDraft.fromPreset(preset)
    XCTAssertEqual(draft.inputMode, .per100g)
    XCTAssertEqual(draft.canonicalServingDescription, "100 g")
    XCTAssertEqual(draft.canonicalQuantity, 1, accuracy: 0.001)
    XCTAssertEqual(draft.totals.calories, 165, accuracy: 0.001)

    draft.amount = 150
    XCTAssertEqual(draft.canonicalQuantity, 1.5, accuracy: 0.001)
    XCTAssertEqual(draft.totals.calories, 247.5, accuracy: 0.001)
    XCTAssertEqual(draft.totals.protein, 46.5, accuracy: 0.001)

    let entry = draft.makeEntry(loggedAt: .now, mealType: .lunch)
    XCTAssertEqual(entry.servingDescription, "100 g")
    XCTAssertEqual(entry.quantity, 1.5, accuracy: 0.001)
    XCTAssertEqual(entry.calories, 247.5, accuracy: 0.001)
    XCTAssertTrue(entry.isValid)
  }

  func testPer100gSentinelIsExactAndNotFuzzy() {
    XCTAssertTrue(FoodPortionMath.isPer100g("100 g"))
    XCTAssertTrue(FoodPortionMath.isPer100g("100g"))
    XCTAssertTrue(FoodPortionMath.isPer100g("每100克"))
    XCTAssertFalse(FoodPortionMath.isPer100g("100 克"))
    XCTAssertFalse(FoodPortionMath.isPer100g("每 100g 装"))
    XCTAssertFalse(FoodPortionMath.isPer100g("1 份（约 100 克）"))
    XCTAssertFalse(FoodPortionMath.isPer100g("1 碗"))
  }

  // MARK: - 最近记录去重

  func testRecentRecordsDeduplicateByNameAndServingAndKeepLatest() throws {
    let older = FoodLogEntry(
      loggedAt: Date(timeIntervalSince1970: 1_000),
      mealType: .breakfast,
      name: "燕麦",
      servingDescription: "1 份",
      quantity: 1,
      calories: 380,
      carbohydrates: 68,
      protein: 13,
      fat: 7
    )
    let newer = FoodLogEntry(
      loggedAt: Date(timeIntervalSince1970: 5_000),
      mealType: .breakfast,
      name: "燕麦",
      servingDescription: "1 份",
      quantity: 2,
      calories: 760,
      carbohydrates: 136,
      protein: 26,
      fat: 14
    )
    let different = FoodLogEntry(
      loggedAt: Date(timeIntervalSince1970: 3_000),
      mealType: .lunch,
      name: "米饭",
      servingDescription: "1 碗",
      quantity: 1,
      calories: 200,
      carbohydrates: 45,
      protein: 4,
      fat: 0.5
    )

    let items = RecentFoodItem.deduplicated(from: [older, different, newer])

    XCTAssertEqual(items.count, 2)
    let oat = try XCTUnwrap(items.first { $0.name == "燕麦" })
    XCTAssertEqual(oat.quantity, 2, accuracy: 0.001)
    XCTAssertEqual(oat.perUnit.calories, 380, accuracy: 0.001)
    XCTAssertEqual(oat.loggedAt, newer.loggedAt)

    var draft = FoodNutritionDraft.fromRecent(oat)
    XCTAssertEqual(draft.totals.calories, 760, accuracy: 0.001)
    draft.amount = 0.5
    XCTAssertEqual(draft.totals.calories, 190, accuracy: 0.001)
  }

  // MARK: - 复制独立性

  func testCopyCreatesIndependentSnapshotsAndPreservesTargetDate() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

    let sourceDay = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 8, minute: 30)))
    let targetDay = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2024, month: 3, day: 15, hour: 0, minute: 0)))

    let presetID = UUID()
    let source = FoodLogEntry(
      loggedAt: sourceDay,
      mealType: .dinner,
      name: "牛肉",
      servingDescription: "100 g",
      quantity: 1.5,
      calories: 300,
      carbohydrates: 0,
      protein: 39,
      fat: 15,
      sourcePresetID: presetID
    )

    let copies = FoodLogCopier.entries(
      copying: [source], to: targetDay, mealType: .lunch, calendar: calendar)

    let copy = try XCTUnwrap(copies.first)
    XCTAssertNotEqual(copy.id, source.id)
    XCTAssertEqual(copy.sourcePresetID, presetID)
    XCTAssertEqual(copy.name, source.name)
    XCTAssertEqual(copy.servingDescription, source.servingDescription)
    XCTAssertEqual(copy.quantity, source.quantity, accuracy: 0.001)
    XCTAssertEqual(copy.calories, source.calories, accuracy: 0.001)
    XCTAssertEqual(copy.mealType, .lunch)
    XCTAssertTrue(calendar.isDate(copy.loggedAt, inSameDayAs: targetDay))
    XCTAssertEqual(calendar.component(.hour, from: copy.loggedAt), 8)
    XCTAssertEqual(calendar.component(.minute, from: copy.loggedAt), 30)

    // 原记录完全不变。
    XCTAssertEqual(source.mealType, .dinner)
    XCTAssertEqual(source.loggedAt, sourceDay)
    XCTAssertEqual(source.calories, 300, accuracy: 0.001)
    XCTAssertNotEqual(copy.loggedAt, source.loggedAt)
  }

  // MARK: - 无效与溢出

  func testInvalidAndOverflowValuesAreRejected() {
    var draft = FoodNutritionDraft(
      name: "边界",
      inputMode: .perServing,
      amount: 1,
      perUnit: NutritionValues(calories: 100, carbohydrates: 10, protein: 10, fat: 5),
      servingDescription: "1 份"
    )
    XCTAssertTrue(draft.isValid)

    draft.amount = 0
    XCTAssertFalse(draft.isValid)
    draft.amount = -1
    XCTAssertFalse(draft.isValid)
    draft.amount = 1

    draft.perUnit.calories = -5
    XCTAssertFalse(draft.isValid)
    draft.perUnit.calories = 100

    draft.perUnit.calories = Double.greatestFiniteMagnitude
    draft.amount = 2
    XCTAssertFalse(draft.totals.isFinite)
    XCTAssertFalse(draft.isValid)

    draft.amount = .infinity
    XCTAssertFalse(draft.isValid)

    draft.name = ""
    XCTAssertFalse(draft.isValid)
  }

  func testZeroValuedIndividualNutrientsRemainValid() {
    let draft = FoodNutritionDraft(
      name: "黑咖啡",
      inputMode: .perServing,
      amount: 1,
      perUnit: NutritionValues(calories: 5, carbohydrates: 0, protein: 0, fat: 0),
      servingDescription: "1 杯"
    )
    XCTAssertTrue(draft.isValid)
    XCTAssertTrue(draft.totals.isValidNonnegative)

    let entry = draft.makeEntry(loggedAt: .now, mealType: .snack)
    XCTAssertTrue(entry.isValid)
    XCTAssertFalse(draft.totals.isAllZero)
  }

  // MARK: - 编辑已有记录

  func testEditingEntryPreservesSnapshotIdentityAndCanonicalValues() {
    let presetID = UUID()
    let entry = FoodLogEntry(
      loggedAt: Date(timeIntervalSince1970: 12_345),
      mealType: .lunch,
      name: "鸡胸肉",
      servingDescription: "100 g",
      quantity: 1.5,
      calories: 247.5,
      carbohydrates: 0,
      protein: 46.5,
      fat: 5.4,
      sourcePresetID: presetID
    )

    var draft = FoodNutritionDraft.fromEntry(entry)
    XCTAssertEqual(draft.inputMode, .per100g)
    XCTAssertEqual(draft.amount, 150, accuracy: 0.001)
    XCTAssertEqual(draft.canonicalQuantity, 1.5, accuracy: 0.001)
    XCTAssertEqual(draft.totals.calories, 247.5, accuracy: 0.001)
    XCTAssertEqual(draft.sourcePresetID, presetID)

    // 改份量自动沿用起始密度。
    draft.amount = 200
    XCTAssertEqual(draft.totals.calories, 330, accuracy: 0.001)

    // 未显式改时间时，调用方传入的 loggedAt 原样保留。
    let updated = draft.makeEntry(loggedAt: entry.loggedAt, mealType: entry.mealType)
    XCTAssertEqual(updated.loggedAt, entry.loggedAt)
    XCTAssertEqual(updated.sourcePresetID, presetID)
  }

  // MARK: - 固定餐份量

  func testMealTemplateApplicationUsesAdjustedQuantitiesAndSnapshots() throws {
    let template = MealTemplate(name: "训练后餐")
    let chicken = MealTemplateItem(
      orderIndex: 0,
      nameSnapshot: "鸡胸肉",
      servingDescriptionSnapshot: "100 g",
      quantity: 1,
      caloriesPerServing: 165,
      carbohydratesPerServing: 0,
      proteinPerServing: 31,
      fatPerServing: 3.6
    )
    let rice = MealTemplateItem(
      orderIndex: 1,
      nameSnapshot: "米饭",
      servingDescriptionSnapshot: "1 碗",
      quantity: 1,
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
      quantities: [chicken.id: 2, rice.id: 0.5],
      mealType: .dinner,
      loggedAt: .now
    )

    XCTAssertEqual(entries.count, 2)
    XCTAssertEqual(entries[0].calories, 330, accuracy: 0.001)
    XCTAssertEqual(entries[1].calories, 100, accuracy: 0.001)
    XCTAssertTrue(entries.allSatisfy { $0.sourceMealTemplateID == template.id })
    XCTAssertTrue(entries.allSatisfy(\.isValid))

    // 快照独立：改模板项不影响已生成记录。
    chicken.proteinPerServing = 99
    XCTAssertEqual(entries[0].protein, 62, accuracy: 0.001)
  }

  // MARK: - 默认餐次

  func testDefaultMealTypeUsesClockHour() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

    func date(hour: Int) throws -> Date {
      try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: hour)))
    }

    XCTAssertEqual(MealType.defaultForTime(try date(hour: 7), calendar: calendar), .breakfast)
    XCTAssertEqual(MealType.defaultForTime(try date(hour: 12), calendar: calendar), .lunch)
    XCTAssertEqual(MealType.defaultForTime(try date(hour: 18), calendar: calendar), .dinner)
    XCTAssertEqual(MealType.defaultForTime(try date(hour: 23), calendar: calendar), .snack)
  }

  // MARK: - 固定餐本地草稿

  func testMealTemplateDraftDoesNotTouchPersistenceBeforeSave() {
    let existing = MealTemplate(name: "原名称")
    let item = MealTemplateItem(
      orderIndex: 0,
      nameSnapshot: "燕麦",
      servingDescriptionSnapshot: "1 份",
      quantity: 1,
      caloriesPerServing: 380,
      carbohydratesPerServing: 68,
      proteinPerServing: 13,
      fatPerServing: 7
    )
    item.template = existing
    existing.items = [item]

    var draft = MealTemplateDraft(template: existing)
    draft.name = "改过的名称"
    draft.remove(id: item.id)

    // 草稿改变，但底层模型没有变。
    XCTAssertEqual(existing.name, "原名称")
    XCTAssertEqual(existing.items.count, 1)
    XCTAssertFalse(draft.isValid)

    let newDraft = MealTemplateDraft(template: nil)
    XCTAssertTrue(newDraft.isNew)
    XCTAssertTrue(newDraft.isEmptyDraft)
    XCTAssertFalse(newDraft.isValid)

    item.quantity = 10_000
    XCTAssertFalse(item.isValid)
    XCTAssertFalse(MealTemplateDraft(template: existing).isValid)
  }
  func testChangingInputBasisPreservesTotalsAndQuantity() {
    var draft = FoodNutritionDraft(name: "米饭", amount: 2, perUnit: NutritionValues(calories: 130))
    let original = draft.totals
    draft.changeInputMode(to: .per100g)
    XCTAssertEqual(draft.amount, 200)
    XCTAssertEqual(draft.totals, original)
    draft.changeInputMode(to: .perServing)
    XCTAssertEqual(draft.amount, 2)
    XCTAssertEqual(draft.totals, original)
  }
}
