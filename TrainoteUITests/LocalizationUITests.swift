import XCTest

final class LocalizationUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
  }

  func testEnglishSystemFirstLaunch() {
    launch(resetLanguage: true, forceSystem: true)
    for title in ["Today", "Training", "Nutrition", "Trends", "Recovery"] {
      XCTAssertTrue(app.tabBars.buttons[title].waitForExistence(timeout: 5), title)
    }
    app.buttons["today.settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["settings.language"].exists)
    capture("English system first launch")
  }

  func testLanguagePreferenceSurvivesRelaunchAndReturnsToSystem() {
    // Do not pass -appearance.language: launch arguments must not override persistence.
    launch(resetLanguage: true)
    app.buttons["today.settings"].tap()
    chooseLanguage("简体中文")
    XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
    capture("Manual Chinese preference")
    app.terminate()
    launch(resetLanguage: false)
    XCTAssertTrue(app.tabBars.buttons["今日"].waitForExistence(timeout: 5))
    app.buttons["today.settings"].tap()
    XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
    chooseLanguage("跟随系统")
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    capture("Returned to English system language")
    app.terminate()
    launch(resetLanguage: false)
    XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
  }

  func testEnglishRecordingEntrancesReportsAndHelp() {
    launch(resetLanguage: true)
    let start = app.buttons["today.startWorkout"]
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    XCTAssertEqual(start.label, "Start workout")
    XCTAssertEqual(app.buttons["today.logFood"].label, "Log food")
    XCTAssertTrue(app.staticTexts["Recorded today"].exists)
    let summary = app.buttons["today.nutritionSummary"]
    reveal(summary)
    XCTAssertEqual(summary.label, "Nutrition · 0 entries")
    summary.tap()
    XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.textFields["nutrition.entry.name"].exists)

    app.tabBars.buttons["Today"].tap()
    app.buttons["today.logFood"].tap()
    XCTAssertTrue(app.textFields["nutrition.entry.name"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["nutrition.entry.sources"].label.contains("Recent"))
    app.navigationBars.buttons["Cancel"].tap()
    XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 5))

    app.tabBars.buttons["Today"].tap()
    app.buttons["today.startWorkout"].tap()
    XCTAssertTrue(app.buttons["training.startBlank"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.navigationBars["Start workout"].exists)
    app.navigationBars.buttons["Cancel"].tap()
    app.tabBars.buttons["Trends"].tap()
    let reports = app.buttons["trends.reports"]
    XCTAssertTrue(reports.waitForExistence(timeout: 5))
    XCTAssertEqual(reports.label, "Reviews and reports")
    reports.tap()
    XCTAssertEqual(app.buttons["today.weeklyReport"].label, "Weekly review and personal records")
    XCTAssertEqual(app.buttons["today.analysisReports"].label, "Reports and history")
    app.buttons["today.weeklyReport"].tap()
    XCTAssertTrue(app.navigationBars["Weekly review"].waitForExistence(timeout: 5))

    app.tabBars.buttons["Today"].tap()
    app.buttons["today.settings"].tap()
    app.buttons["settings.healthHelp"].tap()
    XCTAssertTrue(app.navigationBars["Help and information"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["help.topic.quickStart"].label, "Quick start and terminology")
    app.buttons["help.topic.quickStart"].tap()
    XCTAssertTrue(app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "No routine, body profile, or health permission is required.")
    ).firstMatch.waitForExistence(timeout: 5))
    app.buttons["help.contents"].tap()
    app.buttons["help.topic.nutrition"].tap()
    XCTAssertTrue(app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "Canceling source selection returns to your original draft.")
    ).firstMatch.waitForExistence(timeout: 5))
    capture("English recording routes, reports and help")
  }

  func testActiveWorkoutKeepsDraftFocusCompletedSetAndRestDuringSwitch() {
    launch(resetLanguage: true, controls: true)
    startStrengthWorkout()
    reveal(app.buttons["workout.details"])
    app.buttons["workout.details"].tap()
    let title = app.textFields["workout.title"]
    replace(title, with: "Workout draft 原文")
    dismissKeyboard()
    let weight = app.textFields.matching(
      NSPredicate(format: "identifier BEGINSWITH 'strengthSet.weight.'")
    ).firstMatch
    replace(weight, with: "12.5")
    dismissKeyboard()
    let completion = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'strengthSet.complete.'")
    ).firstMatch
    reveal(completion)
    let completionID = completion.identifier
    completion.tap()
    let rest = app.staticTexts["workout.restRemaining"]
    XCTAssertTrue(rest.waitForExistence(timeout: 5))
    for _ in 0..<8 where !title.isHittable { app.swipeDown() }
    reveal(title)
    title.tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    switchLanguage("zh-Hans")
    XCTAssertTrue(app.navigationBars["进行中"].waitForExistence(timeout: 5))
    XCTAssertEqual(title.value as? String, "Workout draft 原文")
    XCTAssertTrue(app.keyboards.firstMatch.exists, "Switch must preserve the current text responder")
    XCTAssertTrue(rest.exists)
    switchLanguage("en")
    XCTAssertTrue(app.navigationBars["In progress"].waitForExistence(timeout: 5))
    XCTAssertEqual(title.value as? String, "Workout draft 原文")
    XCTAssertTrue(app.keyboards.firstMatch.exists)
    dismissKeyboard()
    reveal(weight)
    XCTAssertEqual(weight.value as? String, "12.5")
    let sameCompletion = app.buttons[completionID]
    reveal(sameCompletion)
    XCTAssertTrue(sameCompletion.label.contains("Completed"))
    capture("Workout state retained after hot language switch")
    app.buttons["workout.finish"].tap()
    XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 5))
  }

  func testIncompleteDecimalAndNutritionDraftSurviveHotSwitchAndSave() {
    verifyNutritionDraft(decimal: ".", region: "en_GB")
  }

  func testCommaDecimalDraftUsesRegionAcrossLanguageSwitch() {
    verifyNutritionDraft(decimal: ",", region: "en_DE")
  }

  func testRoutineDraftSurvivesSwitchAndClosingDoesNotSaveEdits() {
    launch(resetLanguage: true, controls: true)
    app.buttons["today.library"].tap()
    app.buttons["Routines"].tap()
    app.buttons["routine.create"].tap()
    let name = app.textFields["routine.name"]
    replace(name, with: "Routine draft 原文")
    switchLanguage("zh-Hans")
    XCTAssertTrue(app.navigationBars["新建训练模板"].waitForExistence(timeout: 5))
    XCTAssertEqual(name.value as? String, "Routine draft 原文")
    XCTAssertTrue(app.keyboards.firstMatch.exists)
    switchLanguage("en")
    dismissKeyboard()
    app.buttons["routine.addExercise"].tap()
    app.buttons["exercisePicker.item.0001"].tap()
    XCTAssertTrue(app.buttons["routine.save"].isEnabled)
    switchLanguage("zh-Hans")
    XCTAssertEqual(name.value as? String, "Routine draft 原文")
    switchLanguage("en")
    app.buttons["routine.save"].tap()
    let edit = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'routine.edit.'")
    ).firstMatch
    XCTAssertTrue(edit.waitForExistence(timeout: 5))
    edit.tap()
    XCTAssertEqual(name.value as? String, "Routine draft 原文")
    replace(name, with: "Unsaved change")
    switchLanguage("zh-Hans")
    switchLanguage("en")
    dismissKeyboard()
    app.navigationBars.buttons["Close"].tap()
    XCTAssertTrue(edit.waitForExistence(timeout: 5))
    edit.tap()
    XCTAssertEqual(name.value as? String, "Routine draft 原文")
    XCTAssertTrue(app.buttons["routine.save"].isEnabled)
    capture("Routine original retained after closing switched draft")
  }

  private func verifyNutritionDraft(decimal: String, region: String) {
    launch(resetLanguage: true, controls: true, region: region)
    app.tabBars.buttons["Nutrition"].tap()
    app.buttons["nutrition.add"].tap()
    let name = app.textFields["nutrition.entry.name"]
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    replace(name, with: "Meal draft 原文")
    dismissKeyboard()
    let serving = app.textFields["nutrition.entry.serving"]
    replace(serving, with: "My own 1 份 description")
    dismissKeyboard()
    let amount = app.textFields["nutrition.entry.amount"]
    replace(amount, with: "2")
    amount.typeText(decimal)
    XCTAssertEqual(amount.value as? String, "2" + decimal, "Keep incomplete input, including the decimal separator")
    XCTAssertTrue(app.keyboards.firstMatch.exists)
    switchLanguage("zh-Hans")
    XCTAssertEqual(amount.value as? String, "2" + decimal)
    XCTAssertTrue(app.keyboards.firstMatch.exists)
    XCTAssertEqual(name.value as? String, "Meal draft 原文")
    XCTAssertEqual(serving.value as? String, "My own 1 份 description")
    switchLanguage("en")
    XCTAssertEqual(amount.value as? String, "2" + decimal)
    amount.typeText("5")
    XCTAssertEqual(amount.value as? String, "2" + decimal + "5")
    dismissKeyboard()
    XCTAssertTrue(app.buttons["nutrition.entry.save"].exists)
    capture("Nutrition draft retained after hot language switch")
    app.buttons["nutrition.entry.save"].tap()
    XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 5))
    let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Meal draft 原文")).firstMatch
    reveal(saved)
    XCTAssertTrue(saved.exists)
  }

  func testEnglishAccessibilitySizeKeepsWorkoutControlsReachable() {
    launch(resetLanguage: true, controls: true, accessibilitySize: true)
    startStrengthWorkout()
    let complete = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'strengthSet.complete.'")
    ).firstMatch
    let rir = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'strengthSet.rir.'")
    ).firstMatch
    reveal(complete)
    XCTAssertTrue(complete.isHittable)
    let more = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'strengthSet.more.'")
    ).firstMatch
    reveal(more)
    more.tap()
    reveal(rir)
    XCTAssertTrue(rir.isHittable)
    capture("English accessibility workout controls")
  }

  private func launch(
    resetLanguage: Bool, forceSystem: Bool = false, controls: Bool = false,
    accessibilitySize: Bool = false, region: String = "en_GB"
  ) {
    app.launchArguments = ["-ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", region]
    if resetLanguage { app.launchArguments.append("-ui-testing-reset-language") }
    if forceSystem { app.launchArguments += ["-appearance.language", "system"] }
    if controls { app.launchArguments.append("-ui-testing-localization-controls") }
    if accessibilitySize {
      app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-ui-testing-dark"]
    }
    app.launch()
  }

  private func chooseLanguage(_ title: String) {
    let picker = app.buttons["settings.language"]
    XCTAssertTrue(picker.waitForExistence(timeout: 5))
    picker.tap()
    let choice = app.buttons[title]
    XCTAssertTrue(choice.waitForExistence(timeout: 5))
    choice.tap()
  }

  private func startStrengthWorkout() {
    app.tabBars.buttons["Training"].tap()
    app.buttons["training.start"].tap()
    app.buttons["training.startBlank"].tap()
    reveal(app.buttons["workout.addExercise"])
    app.buttons["workout.addExercise"].tap()
    UITestTextInput.replace(app.searchFields.firstMatch, with: "barbell bench press", in: app)
    app.buttons["exercisePicker.item.0025"].tap()
    XCTAssertTrue(app.navigationBars["In progress"].waitForExistence(timeout: 5))
  }

  private func switchLanguage(_ identifier: String) {
    let button = app.buttons["localization.switch.\(identifier)"].firstMatch
    XCTAssertTrue(button.waitForExistence(timeout: 5))
    XCTAssertTrue(button.isHittable)
    button.tap()
    XCTAssertEqual(button.value as? String, identifier)
  }

  private func reveal(_ element: XCUIElement) {
    for _ in 0..<10 where !element.exists || !element.isHittable {
      if element.exists && element.frame.midY < app.frame.midY { app.swipeDown() }
      else { app.swipeUp() }
    }
    XCTAssertTrue(element.waitForExistence(timeout: 5))
    XCTAssertTrue(element.isHittable)
  }

  private func replace(_ field: XCUIElement, with value: String) {
    reveal(field)
    UITestTextInput.replace(field, with: value, in: app)
  }

  private func dismissKeyboard() {
    if app.buttons["Dismiss keyboard"].exists { app.buttons["Dismiss keyboard"].tap() }
    else if app.keyboards.firstMatch.exists && app.buttons["Done"].exists { app.buttons["Done"].firstMatch.tap() }
    XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
