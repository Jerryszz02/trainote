import XCTest

final class DailyUseUpgradeUITests: XCTestCase {
  private var app: XCUIApplication!
  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-appearance.language", "zh-Hans", "-ui-testing"]
    app.launch()
  }

  func testRepeatedWorkoutCreatesPRAndHistoryEditingCanCancel() {
    app.tabBars.buttons["训练"].tap()
    app.buttons["training.start"].tap()
    app.buttons["training.startBlank"].tap()
    app.buttons["workout.addExercise"].tap()
    fill(app.searchFields.firstMatch, "barbell bench press")
    app.buttons["exercisePicker.item.0025"].tap()
    fill(prefix("strengthSet.weight.", type: .textField), "60")
    prefix("strengthSet.complete.").tap()
    XCTAssertTrue(app.staticTexts["workout.restRemaining"].waitForExistence(timeout: 3))
    app.buttons["workout.finish"].tap()
    historyRow.tap()
    app.buttons["training.edit"].tap()
    reveal(app.buttons["workout.details"])
    app.buttons["workout.details"].tap()
    fill(app.textFields["workout.title"], "不应保存")
    app.buttons["workout.edit.cancel"].tap()
    XCTAssertTrue(app.navigationBars["自由训练"].waitForExistence(timeout: 3))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(historyRow.waitForExistence(timeout: 3))
    historyRow.tap()
    XCTAssertTrue(app.navigationBars["自由训练"].waitForExistence(timeout: 3))
    app.buttons["training.repeat"].tap()
    XCTAssertTrue(app.staticTexts["上次表现"].waitForExistence(timeout: 3))
    app.buttons["加重 2.5 公斤"].firstMatch.tap()
    XCTAssertEqual(
      Double(prefix("strengthSet.weight.", type: .textField).value as? String ?? ""), 62.5)
    prefix("strengthSet.complete.").tap()
    app.buttons["workout.finish"].tap()
    // Repeat is nested under the old history detail; return to the training list.
    app.navigationBars.buttons.element(boundBy: 0).tap()
    historyRow.tap()
    XCTAssertTrue(app.staticTexts["突破 PR"].waitForExistence(timeout: 3))
    capture("第二次训练与 PR")
  }

  func testBodyweightAndDurationModesCanBeCompleted() {
    let training = app.tabBars.buttons["训练"]
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        self.app.buttons["today.startWorkout"].isHittable && training.isHittable
      }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed, "首页与训练标签应已就绪")
    // Observe one destination element while navigation settles. Three independent AX queries
    // inside one predicate exhausted CI's wait even though the video showed Training selected.
    training.press(forDuration: 0.15)
    let start = app.buttons["training.start"]
    XCTAssertTrue(start.waitForExistence(timeout: 10), "训练页应显示开始训练入口")
    XCTAssertTrue(training.isSelected, "训练标签应已选中")
    XCTAssertTrue(app.navigationBars["训练"].exists)
    XCTAssertTrue(start.isHittable, "开始训练入口应可点击")
    start.tap()
    let blank = app.buttons["training.startBlank"]
    XCTAssertTrue(blank.waitForExistence(timeout: 3))
    blank.tap()
    app.buttons["workout.addExercise"].tap()
    fill(app.searchFields.firstMatch, "mountain climber")
    app.buttons["exercisePicker.item.0630"].tap()
    XCTAssertFalse(prefix("strengthSet.weight.", type: .textField).exists)
    prefix("strengthSet.complete.").tap()
    reveal(app.buttons["workout.addExercise"])
    app.buttons["workout.addExercise"].tap()
    fill(app.searchFields.firstMatch, "weighted front plank")
    app.buttons["exercisePicker.item.2135"].tap()
    let duration = prefix("strengthSet.duration.", type: .textField)
    reveal(duration)
    fill(duration, "45")
    let complete = app.buttons[duration.identifier.replacingOccurrences(
      of: "strengthSet.duration.", with: "strengthSet.complete.")]
    reveal(complete)
    complete.tap()
    app.buttons["workout.finish"].tap()
    XCTAssertTrue(app.staticTexts["已完成"].waitForExistence(timeout: 3))
  }

  func testReusedCardioRequiresExplicitCompletion() {
    app.tabBars.buttons["训练"].tap()
    app.buttons["training.start"].tap()
    app.buttons["training.startBlank"].tap()
    app.buttons["workout.addExercise"].tap()
    fill(app.searchFields.firstMatch, "跑步")
    app.buttons["exercisePicker.item.0685"].tap()
    fill(app.textFields["cardio.duration"], "10")
    fill(app.textFields["cardio.distance"], "2")
    fill(app.textFields["cardio.calories"], "100")
    app.buttons["workout.finish"].tap()
    historyRow.tap()
    app.buttons["training.repeat"].tap()
    prefix("exercise.history.apply.").tap()
    XCTAssertTrue(app.navigationBars["确认本次有氧成绩"].waitForExistence(timeout: 3))
    capture("有氧历史成绩确认")
    app.buttons["cardio.history.cancel"].tap()
    XCTAssertEqual(app.textFields["cardio.duration"].value as? String, "0")
    XCTAssertEqual(app.textFields["cardio.distance"].value as? String, "0")
    XCTAssertEqual(app.textFields["cardio.calories"].value as? String, "0")
    app.buttons["workout.finish"].tap()
    XCTAssertTrue(app.alerts["请检查记录"].waitForExistence(timeout: 3))
    app.alerts.buttons["知道了"].tap()

    // Cancelling also preserves a result the user already entered for this session.
    // Enter a distinct result without depending on text-selection gestures.
    let duration = app.textFields["cardio.duration"]
    reveal(duration)
    duration.tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
    duration.typeText("4")
    app.buttons["收起键盘"].tap()
    let enteredDuration = duration.value as? String ?? ""
    let enteredMinutes = Double(enteredDuration) ?? 0
    XCTAssertGreaterThan(enteredMinutes, 0)
    XCTAssertNotEqual(enteredMinutes, 10)
    prefix("exercise.history.apply.").tap()
    app.buttons["cardio.history.cancel"].tap()
    XCTAssertEqual(duration.value as? String, enteredDuration)

    prefix("exercise.history.apply.").tap()
    app.buttons["cardio.history.confirm"].tap()
    XCTAssertEqual(app.textFields["cardio.duration"].value as? String, "10")
    XCTAssertEqual(app.textFields["cardio.distance"].value as? String, "2")
    XCTAssertEqual(app.textFields["cardio.calories"].value as? String, "100")
    app.buttons["workout.finish"].tap()
    XCTAssertTrue(app.buttons["training.repeat"].waitForExistence(timeout: 3))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    waitForCount(
      app.buttons.matching(NSPredicate(format: "label CONTAINS '已完成' AND label CONTAINS '自由训练'")), 2
    )
  }

  func testFoodPortionRecentAndWeeklyReport() {
    app.tabBars.buttons["饮食"].tap()
    app.buttons["nutrition.add"].tap()
    fill(app.textFields["nutrition.entry.name"], "验收燕麦")
    selectPer100g("nutrition.entry.basis")
    XCTAssertEqual(app.textFields["nutrition.entry.name"].value as? String, "验收燕麦")
    fill(app.textFields["nutrition.entry.amount"], "150")
    XCTAssertFalse(app.textFields["nutrition.entry.perUnit.calories"].exists)
    XCTAssertFalse(app.textFields["nutrition.entry.total.calories"].exists)
    fill(app.textFields["nutrition.entry.perUnit.carbohydrates"], "70")
    fill(app.textFields["nutrition.entry.perUnit.protein"], "16")
    fill(app.textFields["nutrition.entry.perUnit.fat"], "4")
    app.buttons["nutrition.entry.save"].tap()
    let row = app.buttons.matching(NSPredicate(format: "label CONTAINS '验收燕麦'")).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    XCTAssertTrue(row.label.contains("570 kcal"))
    row.tap()
    fill(app.textFields["nutrition.entry.amount"], "200")
    app.buttons["nutrition.entry.save"].tap()
    XCTAssertTrue(row.label.contains("760 kcal"))
    app.buttons["nutrition.add"].tap()
    app.buttons["nutrition.entry.sources"].tap()
    app.buttons["nutrition.add.recent"].tap()
    prefix("nutrition.recent.item.").tap()
    fill(app.textFields["nutrition.portion.amount"], "50")
    reveal(app.buttons["nutrition.recent.log"])
    app.buttons["nutrition.recent.log"].tap()
    XCTAssertTrue(app.navigationBars["记录最近食物"].waitForNonExistence(timeout: 5))
    waitForCount(app.buttons.matching(NSPredicate(format: "label CONTAINS '验收燕麦'")), 2)
    XCTAssertTrue(
      app.buttons.matching(
        NSPredicate(format: "label CONTAINS '验收燕麦' AND label CONTAINS '190 kcal'")
      ).firstMatch.exists)
    capture("饮食分量与再次记录")
    app.tabBars.buttons["趋势"].tap()
    app.buttons["trends.reports"].tap()
    app.buttons["today.weeklyReport"].tap()
    XCTAssertTrue(app.navigationBars["每周回顾"].waitForExistence(timeout: 3))
    capture("每周回顾")
  }

  func testTodayNutritionSummaryResetsHistoricalDateWithoutOpeningEditor() {
    app.tabBars.buttons["饮食"].tap()
    let datePicker = app.datePickers["nutrition.date"]
    XCTAssertTrue(datePicker.waitForExistence(timeout: 5))
    let todayValue = datePicker.value as? String
    let calendar = Calendar.current
    let today = Date.now
    var components = calendar.dateComponents([.year, .month], from: today)
    components.day = calendar.component(.day, from: today) == 1 ? 2 : 1
    let historicalDate = calendar.date(from: components)!
    datePicker.tap()
    let formatter = DateFormatter()
    var dayLabels = [String(components.day!)]
    for locale in [Locale.current, Locale(identifier: "en_US"), Locale(identifier: "zh_CN")] {
      formatter.locale = locale
      formatter.dateStyle = .full
      dayLabels.append(formatter.string(from: historicalDate))
      for format in ["EEEE, MMMM d", "EEEE, d MMMM", "d MMMM", "M月d日 EEEE"] {
        formatter.dateFormat = format
        dayLabels.append(formatter.string(from: historicalDate))
      }
    }
    let day = app.buttons.matching(NSPredicate(format: "label IN %@", dayLabels)).firstMatch
    XCTAssertTrue(day.waitForExistence(timeout: 3), app.debugDescription)
    day.tap()
    app.navigationBars["饮食"].tap()
    let historicalValue = datePicker.value as? String
    XCTAssertNotEqual(historicalValue, todayValue, "应先选中另一天，复现饮食日期保留的情况")

    // Ordinary tab navigation should preserve the day the user is reviewing.
    app.tabBars.buttons["今日"].tap()
    app.tabBars.buttons["饮食"].tap()
    XCTAssertEqual(datePicker.value as? String, historicalValue)
    app.tabBars.buttons["今日"].tap()
    reveal(app.buttons["today.nutritionSummary"])
    app.buttons["today.nutritionSummary"].tap()
    XCTAssertTrue(datePicker.waitForExistence(timeout: 5))
    XCTAssertEqual(datePicker.value as? String, todayValue)
    XCTAssertFalse(app.textFields["nutrition.entry.name"].exists)
    XCTAssertTrue(app.buttons["nutrition.add"].isHittable)

    // The separate quick action must continue opening a new entry editor.
    app.tabBars.buttons["今日"].tap()
    app.buttons["today.logFood"].tap()
    XCTAssertTrue(app.textFields["nutrition.entry.name"].waitForExistence(timeout: 5))
  }

  func testEmptyWorkoutCannotFinishAndFailedGoalSaveIsVisible() {
    app.tabBars.buttons["训练"].tap()
    app.buttons["training.start"].tap()
    app.buttons["training.startBlank"].tap()
    app.buttons["workout.finish"].tap()
    XCTAssertTrue(app.alerts["请检查记录"].waitForExistence(timeout: 3))
    app.terminate()
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-appearance.language", "zh-Hans", "-ui-testing", "-ui-testing-readonly"]
    app.launch()
    app.buttons["today.settings"].tap()
    app.buttons["每日营养目标"].tap()
    app.buttons["goal.save"].tap()
    XCTAssertTrue(app.alerts["保存失败"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["已保存"].exists)
  }

  func testTrainingDraftAndRestTimerSurviveRelaunch() {
    app.terminate()
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-appearance.language", "zh-Hans", "-ui-testing-persistent"]
    app.launch()
    app.tabBars.buttons["训练"].tap()
    if app.buttons["training.activeWorkout"].exists {
      app.buttons["training.activeWorkout"].tap()
      reveal(app.buttons["workout.discard"])
      app.buttons["workout.discard"].tap()
      app.buttons["放弃并删除"].tap()
    }
    app.buttons["training.start"].tap()
    app.buttons["training.startBlank"].tap()
    let title = "重启训练-\(UUID().uuidString.prefix(6))"
    reveal(app.buttons["workout.details"])
    app.buttons["workout.details"].tap()
    fill(app.textFields["workout.title"], title)
    app.buttons["workout.addExercise"].tap()
    app.buttons["exercisePicker.item.0001"].tap()
    prefix("strengthSet.complete.").tap()
    XCTAssertTrue(app.staticTexts["workout.restRemaining"].waitForExistence(timeout: 3))
    app.terminate()
    app.launch()
    let resume = app.buttons["today.startWorkout"]
    XCTAssertTrue(resume.waitForExistence(timeout: 5))
    XCTAssertTrue(resume.label.contains("继续训练"))
    resume.tap()
    reveal(app.buttons["workout.details"])
    app.buttons["workout.details"].tap()
    XCTAssertEqual(app.textFields["workout.title"].value as? String, title)
    let rest = app.staticTexts["workout.restRemaining"]
    // The settings section is below the exercises; List materializes the timer at the top.
    for _ in 0..<3 { app.swipeDown() }
    XCTAssertTrue(rest.exists)
    reveal(prefix("strengthSet.complete."))
    XCTAssertTrue(prefix("strengthSet.complete.").label.contains("已完成"))
    app.buttons["workout.finish"].tap()
    assertFinishedWithoutRestart(title: title)
  }

  func testTodayStartContinueAndFinishConsumesRequest() {
    app.buttons["today.startWorkout"].tap()
    app.buttons["training.startBlank"].tap()
    XCTAssertTrue(app.buttons["workout.addExercise"].waitForExistence(timeout: 5))
    app.buttons["workout.addExercise"].tap()
    app.buttons["exercisePicker.item.0001"].tap()
    // Return to the training root before taking the distinct Today continuation route.
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.tabBars.buttons["今日"].tap()
    app.buttons["today.startWorkout"].tap()
    prefix("strengthSet.complete.").tap()
    app.buttons["workout.finish"].tap()
    assertFinishedWithoutRestart(title: "自由训练")
  }

  func testTodayContinueWhileTrainingDetailRemainsOpenFinishesWithoutRestart() {
    app.tabBars.buttons["训练"].tap()
    app.buttons["training.start"].tap()
    app.buttons["training.startBlank"].tap()
    app.buttons["workout.addExercise"].tap()
    app.buttons["exercisePicker.item.0001"].tap()
    app.tabBars.buttons["今日"].tap()
    app.buttons["today.startWorkout"].tap()
    prefix("strengthSet.complete.").tap()
    app.buttons["workout.finish"].tap()
    assertFinishedWithoutRestart(title: "自由训练")
  }

  func testFixedMealPortionAndCopyToAnotherMeal() {
    app.tabBars.buttons["今日"].tap()
    app.buttons["today.library"].tap()
    app.segmentedControls.buttons["饮食"].tap()
    app.buttons["foodLibrary.create"].tap()
    fill(app.textFields["foodPreset.name"], "固定餐燕麦")
    selectPer100g("foodPreset.basis")
    XCTAssertEqual(app.textFields["foodPreset.name"].value as? String, "固定餐燕麦")
    XCTAssertFalse(app.textFields["foodPreset.nutrient.卡路里"].exists)
    fill(app.textFields["foodPreset.nutrient.碳水"], "25")
    app.buttons["foodPreset.save"].tap()
    app.segmentedControls.buttons["固定餐"].tap()
    app.buttons["foodLibrary.create"].tap()
    fill(app.textFields["mealTemplate.name"], "日常午餐")
    app.buttons["mealTemplate.addPreset"].tap()
    app.buttons.matching(NSPredicate(format: "label CONTAINS '固定餐燕麦'")).firstMatch.tap()
    app.buttons["mealTemplate.save"].tap()
    app.tabBars.buttons["饮食"].tap()
    app.buttons["nutrition.add"].tap()
    app.buttons["nutrition.entry.sources"].tap()
    app.buttons["nutrition.add.meal"].tap()
    prefix("nutrition.meal.template.").tap()
    app.buttons["nutrition.meal.type"].tap()
    app.buttons["午餐"].tap()
    fill(prefix("nutrition.meal.quantity.", type: .textField), "200")
    reveal(app.buttons["nutrition.meal.apply"])
    app.buttons["nutrition.meal.apply"].tap()
    let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS '固定餐燕麦'"))
    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 3))
    XCTAssertTrue(rows.firstMatch.label.contains("200"))
    app.buttons["nutrition.add"].tap()
    app.buttons["nutrition.entry.sources"].tap()
    app.buttons["nutrition.add.copy"].tap()
    app.buttons["nutrition.copy.today"].tap()
    app.buttons["nutrition.copy.sourceMeal"].tap()
    app.buttons["午餐"].tap()
    app.buttons["nutrition.copy.targetMeal"].tap()
    app.buttons["晚餐"].tap()
    reveal(app.buttons["nutrition.copy.confirm"])
    app.buttons["nutrition.copy.confirm"].tap()
    app.buttons["复制"].tap()
    // List exposes rows lazily; the diet-completeness section can push dinner offscreen.
    for _ in 0..<4 where rows.count < 2 { app.swipeUp() }
    waitForCount(rows, 2)
    capture("固定餐与复制一餐")
  }

  func testDirectFoodDraftSurvivesEverySourceCancellationAndTotalCorrection() {
    app.buttons["today.logFood"].tap()
    XCTAssertTrue(app.textFields["nutrition.entry.name"].waitForExistence(timeout: 5))
    fill(app.textFields["nutrition.entry.name"], "草稿燕麦")
    fill(app.textFields["nutrition.entry.perUnit.carbohydrates"], "25")
    for source in ["recent", "preset", "meal", "copy"] {
      let sources = app.buttons["nutrition.entry.sources"]
      for _ in 0..<8 where !sources.isHittable { app.swipeDown() }
      sources.tap()
      app.buttons["nutrition.add.\(source)"].tap()
      app.buttons["nutrition.source.cancel"].tap()
      XCTAssertEqual(app.textFields["nutrition.entry.name"].value as? String, "草稿燕麦")
    }
    fill(app.textFields["nutrition.entry.amount"], "2")
    let totals = app.buttons["nutrition.entry.editTotals"]
    reveal(totals)
    totals.tap()
    fill(app.textFields["nutrition.entry.total.carbohydrates"], "60")
    for _ in 0..<8 where !app.textFields["nutrition.entry.amount"].isHittable { app.swipeDown() }
    fill(app.textFields["nutrition.entry.amount"], "3")
    app.navigationBars.buttons["取消"].tap()
    XCTAssertTrue(app.buttons["放弃草稿"].waitForExistence(timeout: 3))
    app.buttons["继续编辑"].tap()
    app.buttons["nutrition.entry.save"].tap()
    let row = app.buttons.matching(NSPredicate(format: "label CONTAINS '草稿燕麦'")).firstMatch
    reveal(row)
    XCTAssertTrue(row.label.contains("360 kcal"))
    row.tap()
    XCTAssertEqual(app.textFields["nutrition.entry.amount"].value as? String, "3")
    app.buttons["nutrition.entry.save"].tap()
    XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS '草稿燕麦'")).count, 1)
    capture("直接记餐与总量修正回读")
  }

  func testContinueKeepsTheSameSetAndOptionalValues() {
    app.buttons["today.startWorkout"].tap()
    app.buttons["training.startBlank"].tap()
    XCTAssertFalse(app.textFields["workout.title"].exists)
    app.buttons["workout.addExercise"].tap()
    fill(app.searchFields.firstMatch, "bench")
    app.buttons["exercisePicker.item.0025"].tap()
    let set = prefix("strengthSet.complete.")
    let identifier = set.identifier
    XCTAssertTrue(set.label.contains("完成本组"))
    fill(prefix("strengthSet.weight.", type: .textField), "20")
    let more = prefix("strengthSet.more.")
    reveal(more)
    more.tap()
    let rir = prefix("strengthSet.rir.")
    rir.tap()
    app.buttons["2 次"].tap()
    more.tap()
    XCTAssertFalse(rir.exists)
    app.tabBars.buttons["今日"].tap()
    app.buttons["today.startWorkout"].tap()
    XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 3))
    XCTAssertEqual(prefix("strengthSet.weight.", type: .textField).value as? String, "20")
    reveal(more)
    more.tap()
    XCTAssertTrue(rir.label.contains("2 次"))
    app.buttons[identifier].tap()
    XCTAssertEqual(app.buttons["workout.finish"].label, "结束训练")
    app.buttons["workout.finish"].tap()
    historyRow.tap()
    XCTAssertTrue(app.staticTexts["20 kg × 8 次"].exists)
    capture("同一训练组与历史回读")
  }

  private var historyRow: XCUIElement {
    app.buttons.matching(NSPredicate(format: "label CONTAINS '已完成' AND label CONTAINS '自由训练'"))
      .firstMatch
  }
  private func assertFinishedWithoutRestart(title: String) {
    let completed = app.buttons.matching(
      NSPredicate(format: "label CONTAINS '已完成' AND label CONTAINS %@", title))
    XCTAssertTrue(completed.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(completed.count, 1)
    XCTAssertFalse(app.buttons["training.activeWorkout"].exists)
    XCTAssertFalse(app.buttons["training.startBlank"].waitForExistence(timeout: 2))
    capture("今日继续完成后保留历史")
    // A later explicit start must still work after the previous intent was consumed.
    app.buttons["training.start"].tap()
    XCTAssertTrue(app.buttons["training.startBlank"].waitForExistence(timeout: 3))
    app.buttons["取消"].tap()
  }
  private func prefix(_ identifier: String, type: XCUIElement.ElementType = .button) -> XCUIElement
  {
    app.descendants(matching: type).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", identifier)
    ).firstMatch
  }
  private func reveal(_ element: XCUIElement) {
    for _ in 0..<10 {
      if element.exists && element.isHittable { return }
      app.swipeUp()
    }
  }
  private func waitForCount(_ query: XCUIElementQuery, _ expected: Int) {
    let updated = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in query.count == expected }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
    XCTAssertEqual(query.count, expected)
  }
  private func selectPer100g(_ identifier: String) {
    let option = app.segmentedControls[identifier].buttons["按每 100 克"]
    reveal(option)
    XCTAssertTrue(option.waitForExistence(timeout: 5))
    option.tap()
  }
  private func fill(_ field: XCUIElement, _ value: String) {
    reveal(field)
    UITestTextInput.replace(field, with: value, in: app)
  }
  private func capture(_ title: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = title
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
