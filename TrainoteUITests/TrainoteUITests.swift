import XCTest

final class TrainoteUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
    app.launch()
  }

  func testMainTabsAreAvailable() {
    XCTAssertTrue(app.tabBars.buttons["今日"].exists)
    XCTAssertTrue(app.tabBars.buttons["训练"].exists)
    XCTAssertTrue(app.tabBars.buttons["饮食"].exists)
    XCTAssertTrue(app.tabBars.buttons["资料库"].exists)
  }

  func testCanStartBlankWorkoutAndResumeIt() {
    startBlankWorkout()
    XCTAssertTrue(app.buttons["training.activeWorkout"].waitForExistence(timeout: 3))
  }

  func testCanCompleteStrengthWorkout() {
    startBlankWorkout()
    app.buttons["training.activeWorkout"].tap()
    app.buttons["workout.addExercise"].tap()
    app.buttons["exercisePicker.item.0001"].tap()
    XCTAssertFalse(app.textFields["cardio.duration"].exists)
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'strengthSet.complete.'"))
      .firstMatch.tap()
    app.buttons["workout.finish"].tap()

    XCTAssertTrue(app.staticTexts["已完成"].waitForExistence(timeout: 3))
  }

  func testCanCompleteCardioWorkout() {
    startBlankWorkout()
    app.buttons["training.activeWorkout"].tap()
    app.buttons["workout.addExercise"].tap()
    replaceText(in: app.searchFields.firstMatch, with: "跑步")
    app.buttons["exercisePicker.item.0685"].tap()
    XCTAssertFalse(
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'strengthSet.complete.'"))
        .firstMatch.exists
    )
    replaceText(in: app.textFields["cardio.duration"], with: "10")
    app.buttons["workout.finish"].tap()

    XCTAssertTrue(app.staticTexts["已完成"].waitForExistence(timeout: 3))
  }

  func testCanCreateAndStartRoutine() {
    app.tabBars.buttons["资料库"].tap()
    app.buttons["Routine"].tap()
    app.buttons["routine.create"].tap()
    app.buttons["routine.addExercise"].tap()
    app.buttons["exercisePicker.item.0001"].tap()
    app.buttons["routine.save"].tap()

    app.tabBars.buttons["训练"].tap()
    app.buttons["training.start"].tap()
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'training.startRoutine.'"))
      .firstMatch.tap()

    XCTAssertTrue(app.buttons["training.activeWorkout"].waitForExistence(timeout: 3))
  }

  func testFoodEntryCanBeAddedEditedAndDeleted() {
    openDirectFoodEditor()
    replaceText(in: app.textFields["nutrition.entry.name"], with: "测试早餐")
    app.buttons["nutrition.entry.save"].tap()

    let row = app.buttons.matching(NSPredicate(format: "label CONTAINS '测试早餐'"))
      .firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.tap()
    replaceText(in: app.textFields["nutrition.entry.name"], with: "测试早午餐")
    app.buttons["nutrition.entry.save"].tap()

    let editedRow = app.buttons.matching(NSPredicate(format: "label CONTAINS '测试早午餐'"))
      .firstMatch
    XCTAssertTrue(editedRow.waitForExistence(timeout: 3))
    editedRow.swipeLeft()
    app.buttons["删除"].tap()
    app.alerts.buttons["删除"].tap()
    XCTAssertFalse(editedRow.exists)
  }

  func testCommonFoodCanBeReused() {
    openDirectFoodEditor()
    replaceText(in: app.textFields["nutrition.entry.name"], with: "测试香蕉")
    app.switches["同时保存为常用食物"].tap()
    app.buttons["nutrition.entry.save"].tap()

    app.buttons["nutrition.add"].tap()
    app.buttons["从常用食物记录"].tap()
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'foodPreset.log.'"))
      .firstMatch.tap()

    XCTAssertEqual(
      app.buttons.matching(NSPredicate(format: "label CONTAINS '测试香蕉'")).count,
      2
    )
  }

  func testPersistentDataSurvivesRelaunch() {
    app.terminate()
    app = XCUIApplication()
    app.launchArguments = ["-ui-testing-persistent"]
    app.launch()
    let uniqueName = "重启记录-\(UUID().uuidString.prefix(8))"

    openDirectFoodEditor()
    replaceText(in: app.textFields["nutrition.entry.name"], with: uniqueName)
    app.buttons["nutrition.entry.save"].tap()
    app.terminate()
    app.launch()
    app.tabBars.buttons["饮食"].tap()

    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label CONTAINS %@", uniqueName)).firstMatch
        .waitForExistence(timeout: 3)
    )
  }

  func testSettingsCanOpenNutritionGoal() {
    app.buttons["today.settings"].tap()
    XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 3))
    app.buttons["每日营养目标"].tap()
    XCTAssertTrue(app.navigationBars["营养目标"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["goal.save"].exists)
    app.buttons["goal.save"].tap()
    XCTAssertTrue(app.buttons["已保存"].exists)
  }

  private func startBlankWorkout() {
    app.tabBars.buttons["训练"].tap()
    app.buttons["training.start"].tap()
    app.buttons["training.startBlank"].tap()
  }

  private func openDirectFoodEditor() {
    app.tabBars.buttons["饮食"].tap()
    app.buttons["nutrition.add"].tap()
    app.buttons["直接记录"].tap()
  }

  private func replaceText(in field: XCUIElement, with value: String) {
    XCTAssertTrue(field.waitForExistence(timeout: 3))
    field.tap()
    field.typeKey("a", modifierFlags: .command)
    field.typeText(value)
  }
}
