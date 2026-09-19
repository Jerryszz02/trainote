import XCTest

final class DailyUseUpgradeUITests: XCTestCase {
  private var app: XCUIApplication!
  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
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
    fill(app.textFields["workout.title"], "不应保存")
    app.buttons["workout.edit.cancel"].tap()
    XCTAssertFalse(app.navigationBars["不应保存"].exists)
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
    app.tabBars.buttons["训练"].tap()
    app.buttons["training.start"].tap()
    app.buttons["training.startBlank"].tap()
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
    let complete = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'strengthSet.complete.'")
    ).element(boundBy: 1)
    reveal(complete)
    complete.tap()
    app.buttons["workout.finish"].tap()
    XCTAssertTrue(app.staticTexts["已完成"].waitForExistence(timeout: 3))
  }

  func testFoodPortionRecentAndWeeklyReport() {
    app.tabBars.buttons["饮食"].tap()
    app.buttons["nutrition.add"].tap()
    app.buttons["nutrition.add.direct"].tap()
    fill(app.textFields["nutrition.entry.name"], "验收燕麦")
    app.buttons["nutrition.entry.basis"].tap()
    app.buttons["按每 100 克"].tap()
    fill(app.textFields["nutrition.entry.amount"], "150")
    fill(app.textFields["nutrition.entry.perUnit.calories"], "380")
    app.buttons["nutrition.entry.save"].tap()
    let row = app.buttons.matching(NSPredicate(format: "label CONTAINS '验收燕麦'")).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    XCTAssertTrue(row.label.contains("570 kcal"))
    row.tap()
    fill(app.textFields["nutrition.entry.amount"], "200")
    app.buttons["nutrition.entry.save"].tap()
    XCTAssertTrue(row.label.contains("760 kcal"))
    app.buttons["nutrition.add"].tap()
    app.buttons["nutrition.add.recent"].tap()
    prefix("nutrition.recent.item.").tap()
    fill(app.textFields["nutrition.portion.amount"], "50")
    reveal(app.buttons["nutrition.recent.log"])
    app.buttons["nutrition.recent.log"].tap()
    XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS '验收燕麦'")).count, 2)
    XCTAssertTrue(
      app.buttons.matching(
        NSPredicate(format: "label CONTAINS '验收燕麦' AND label CONTAINS '190 kcal'")
      ).firstMatch.exists)
    capture("饮食分量与再次记录")
    app.tabBars.buttons["今日"].tap()
    reveal(app.buttons["today.weeklyReport"])
    app.buttons["today.weeklyReport"].tap()
    XCTAssertTrue(app.navigationBars["每周回顾"].waitForExistence(timeout: 3))
    capture("每周回顾")
  }

  func testEmptyWorkoutCannotFinishAndFailedGoalSaveIsVisible() {
    app.tabBars.buttons["训练"].tap()
    app.buttons["training.start"].tap()
    app.buttons["training.startBlank"].tap()
    app.buttons["workout.finish"].tap()
    XCTAssertTrue(app.alerts["请检查记录"].waitForExistence(timeout: 3))
    app.terminate()
    app.launchArguments = ["-ui-testing", "-ui-testing-readonly"]
    app.launch()
    app.buttons["today.settings"].tap()
    app.buttons["每日营养目标"].tap()
    app.buttons["goal.save"].tap()
    XCTAssertTrue(app.alerts["保存失败"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["已保存"].exists)
  }

  func testTrainingDraftAndRestTimerSurviveRelaunch() {
    app.terminate()
    app.launchArguments = ["-ui-testing-persistent"]
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
    fill(app.textFields["workout.title"], title)
    app.buttons["workout.addExercise"].tap()
    app.buttons["exercisePicker.item.0001"].tap()
    prefix("strengthSet.complete.").tap()
    XCTAssertTrue(app.staticTexts["workout.restRemaining"].waitForExistence(timeout: 3))
    app.terminate()
    app.launch()
    app.tabBars.buttons["训练"].tap()
    app.buttons["training.activeWorkout"].tap()
    XCTAssertEqual(app.textFields["workout.title"].value as? String, title)
    XCTAssertTrue(app.staticTexts["workout.restRemaining"].exists)
    XCTAssertTrue(prefix("strengthSet.complete.").label.contains("已完成"))
    reveal(app.buttons["workout.discard"])
    app.buttons["workout.discard"].tap()
    app.buttons["放弃并删除"].tap()
  }

  func testFixedMealPortionAndCopyToAnotherMeal() {
    app.tabBars.buttons["资料库"].tap()
    app.segmentedControls.buttons["饮食"].tap()
    app.buttons["foodLibrary.create"].tap()
    fill(app.textFields["foodPreset.name"], "固定餐燕麦")
    app.buttons["foodPreset.basis"].tap()
    app.buttons["按每 100 克"].tap()
    fill(app.textFields["foodPreset.nutrient.卡路里"], "100")
    app.buttons["foodPreset.save"].tap()
    app.segmentedControls.buttons["固定餐"].tap()
    app.buttons["foodLibrary.create"].tap()
    fill(app.textFields["mealTemplate.name"], "日常午餐")
    app.buttons["mealTemplate.addPreset"].tap()
    app.buttons.matching(NSPredicate(format: "label CONTAINS '固定餐燕麦'")).firstMatch.tap()
    app.buttons["mealTemplate.save"].tap()
    app.tabBars.buttons["饮食"].tap()
    app.buttons["nutrition.add"].tap()
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
    app.buttons["nutrition.add.copy"].tap()
    app.buttons["nutrition.copy.today"].tap()
    app.buttons["nutrition.copy.sourceMeal"].tap()
    app.buttons["午餐"].tap()
    app.buttons["nutrition.copy.targetMeal"].tap()
    app.buttons["晚餐"].tap()
    reveal(app.buttons["nutrition.copy.confirm"])
    app.buttons["nutrition.copy.confirm"].tap()
    app.buttons["复制"].tap()
    XCTAssertEqual(rows.count, 2)
    capture("固定餐与复制一餐")
  }

  private var historyRow: XCUIElement {
    app.buttons.matching(NSPredicate(format: "label CONTAINS '已完成' AND label CONTAINS '自由训练'"))
      .firstMatch
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
  private func fill(_ field: XCUIElement, _ value: String) {
    reveal(field)
    XCTAssertTrue(field.waitForExistence(timeout: 3))
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
    let current = field.value as? String ?? ""
    if Double(current.replacingOccurrences(of: ",", with: "")) != nil {
      field.press(forDuration: 1.1)
      let selectAll = app.buttons.matching(NSPredicate(format: "label IN {'Select All', '全选'}"))
        .firstMatch
      let menuSelectAll = app.menuItems.matching(
        NSPredicate(format: "label IN {'Select All', '全选'}")
      ).firstMatch
      if selectAll.waitForExistence(timeout: 1) {
        selectAll.tap()
      } else if menuSelectAll.exists {
        menuSelectAll.tap()
      } else {
        field.doubleTap()
      }
    } else {
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 1))
    }
    field.typeText(value)
    if let expected = Double(value),
      let actual = Double((field.value as? String ?? "").replacingOccurrences(of: ",", with: ""))
    {
      XCTAssertEqual(actual, expected, accuracy: 0.000_001)
    } else {
      XCTAssertEqual(field.value as? String, value)
    }
    if app.buttons["收起键盘"].exists {
      app.buttons["收起键盘"].tap()
    } else if field.identifier.hasPrefix("nutrition.") || field.identifier.hasPrefix("foodPreset.")
      || field.identifier.hasPrefix("mealTemplate.")
    {
      if app.keyboards.count > 0 && app.buttons["完成"].exists {
        app.buttons["完成"].firstMatch.tap()
      }
    }
  }
  private func capture(_ title: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = title
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
