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
    XCTAssertTrue(app.tabBars.buttons["趋势"].exists)
    XCTAssertTrue(app.tabBars.buttons["恢复"].exists)
    XCTAssertEqual(app.tabBars.buttons.count, 5)
    XCTAssertTrue(app.buttons["today.library"].exists)
  }

  func testCanStartBlankWorkoutAndResumeIt() {
    startBlankWorkout()
    XCTAssertTrue(app.navigationBars["进行中"].waitForExistence(timeout: 5))
  }

  func testExerciseSampleCanPauseAndPlayAndOtherExercisesKeepInstructions() {
    app.buttons["today.library"].tap()
    replaceText(in: app.searchFields.firstMatch, with: "push-up")
    app.searchFields.firstMatch.typeText("\n")
    let sample = app.buttons["exerciseLibrary.item.0662"]
    // Variations precede the ordinary push-up in the bundled catalog; List is lazy.
    for _ in 0..<12 where !sample.exists || !sample.isHittable { app.swipeUp() }
    XCTAssertTrue(sample.waitForExistence(timeout: 5))
    sample.tap()
    let toggle = app.buttons["exerciseAnimation.toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    let ready = NSPredicate(format: "enabled == true")
    expectation(for: ready, evaluatedWith: toggle)
    waitForExpectations(timeout: 10)
    if toggle.value as? String == "播放中" { toggle.tap() }
    XCTAssertEqual(toggle.value as? String, "已暂停")
    toggle.tap()
    XCTAssertEqual(toggle.value as? String, "播放中")
    toggle.tap()
    XCTAssertEqual(toggle.value as? String, "已暂停")
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "俯卧撑离线动态演示"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    reveal(app.buttons["exercise.sources"])
    app.buttons["exercise.sources"].tap()
    XCTAssertTrue(app.navigationBars["帮助与说明"].waitForExistence(timeout: 3))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.navigationBars["动作详情"].waitForExistence(timeout: 3))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    replaceText(in: app.searchFields.firstMatch, with: "3/4 sit-up")
    app.searchFields.firstMatch.typeText("\n")
    app.buttons["exerciseLibrary.item.0001"].tap()
    XCTAssertFalse(app.staticTexts["exerciseAnimation.notCollected"].exists)
    XCTAssertFalse(app.buttons["exerciseAnimation.toggle"].exists)
    XCTAssertTrue(app.staticTexts["分类"].exists)
    for _ in 0..<4 where !app.staticTexts["中文说明"].exists { app.swipeUp() }
    XCTAssertTrue(app.staticTexts["中文说明"].exists)
  }

  func testCanCompleteStrengthWorkout() {
    startBlankWorkout()
    app.buttons["workout.addExercise"].tap()
    app.buttons["exercisePicker.item.0001"].tap()
    XCTAssertFalse(app.textFields["cardio.duration"].exists)
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'strengthSet.complete.'"))
      .firstMatch.tap()
    app.buttons["workout.finish"].tap()

    XCTAssertTrue(app.staticTexts["已完成"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["training.startBlank"].waitForExistence(timeout: 2))
  }

  func testCanCompleteCardioWorkout() {
    startBlankWorkout()
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
    app.tabBars.buttons["今日"].tap()
    app.buttons["today.library"].tap()
    app.buttons["训练模板"].tap()
    app.buttons["routine.create"].tap()
    app.buttons["routine.addExercise"].tap()
    app.buttons["exercisePicker.item.0001"].tap()
    app.buttons["routine.save"].tap()

    let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'routine.edit.'"))
      .firstMatch
    XCTAssertTrue(edit.waitForExistence(timeout: 3))
    edit.tap()
    XCTAssertTrue(app.navigationBars["编辑训练模板"].waitForExistence(timeout: 3))
    app.buttons["routine.save"].tap()
    let start = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'routine.start.'"))
      .firstMatch
    XCTAssertTrue(start.waitForExistence(timeout: 3))
    start.tap()

    XCTAssertTrue(app.navigationBars["进行中"].waitForExistence(timeout: 5))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.buttons["routine.continueWorkout"].waitForExistence(timeout: 3))
    XCTAssertFalse(start.isEnabled)
    app.buttons["routine.continueWorkout"].tap()
    XCTAssertTrue(app.navigationBars["进行中"].waitForExistence(timeout: 3))
  }

  func testFoodEntryCanBeAddedEditedAndDeleted() {
    openDirectFoodEditor()
    replaceText(in: app.textFields["nutrition.entry.name"], with: "测试早餐")
    app.buttons["nutrition.entry.save"].tap()

    let row = app.buttons.matching(NSPredicate(format: "label CONTAINS '测试早餐'"))
      .firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    revealFoodRow(row)
    row.tap()
    XCTAssertTrue(app.navigationBars["编辑饮食"].waitForExistence(timeout: 5))
    replaceText(in: app.textFields["nutrition.entry.name"], with: "测试早午餐")
    app.buttons["nutrition.entry.save"].tap()

    let editedRow = app.buttons.matching(NSPredicate(format: "label CONTAINS '测试早午餐'"))
      .firstMatch
    XCTAssertTrue(editedRow.waitForExistence(timeout: 3))
    revealFoodRow(editedRow)
    editedRow.swipeLeft()
    app.buttons["删除"].tap()
    app.alerts.buttons["删除"].tap()
    XCTAssertFalse(editedRow.exists)
  }

  func testCommonFoodCanBeReused() {
    openDirectFoodEditor()
    replaceText(in: app.textFields["nutrition.entry.name"], with: "测试香蕉")
    let savePreset = app.switches["nutrition.entry.savePreset"]
    reveal(savePreset)
    savePreset.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
    XCTAssertEqual(savePreset.value as? String, "1")
    app.buttons["nutrition.entry.save"].tap()

    app.buttons["nutrition.add"].tap()
    app.buttons["nutrition.entry.sources"].tap()
    app.buttons["nutrition.add.preset"].tap()
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'foodPreset.log.'"))
      .firstMatch.tap()
    reveal(app.buttons["nutrition.preset.log"])
    app.buttons["nutrition.preset.log"].tap()
    XCTAssertTrue(app.navigationBars["记录常用食物"].waitForNonExistence(timeout: 5))
    let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS '测试香蕉'"))
    // Materialize both saved rows below the summary before checking the List's count.
    for _ in 0..<4 where rows.count < 2 { app.swipeUp() }
    let updated = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in rows.count == 2 }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
    XCTAssertEqual(rows.count, 2)

    app.buttons["nutrition.add"].tap()
    replaceText(in: app.textFields["nutrition.entry.name"], with: "保留的草稿")
    app.buttons["nutrition.entry.sources"].tap()
    app.buttons["nutrition.add.preset"].tap()
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'foodPreset.log.'"))
      .firstMatch.tap()
    reveal(app.buttons["nutrition.preset.log"])
    app.buttons["nutrition.preset.log"].tap()
    XCTAssertTrue(app.staticTexts["nutrition.entry.draftRetained"].waitForExistence(timeout: 3))
    XCTAssertEqual(app.textFields["nutrition.entry.name"].value as? String, "保留的草稿")
    app.navigationBars.buttons["取消"].tap()
    app.alerts.buttons["放弃草稿"].tap()
    for _ in 0..<4 where rows.count < 3 { app.swipeUp() }
    XCTAssertEqual(rows.count, 3)
    XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS '保留的草稿'")).firstMatch.exists)
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

  func testAboutShowsPrivacyAndSupportLinks() {
    app.buttons["today.settings"].tap()
    XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 3))
    reveal(app.buttons["Trainote 与数据来源"])
    app.buttons["Trainote 与数据来源"].tap()

    XCTAssertTrue(app.navigationBars["帮助与说明"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["help.license.THIRD_PARTY_NOTICES"].exists)
  }

  private func startBlankWorkout() {
    app.tabBars.buttons["训练"].tap()
    app.buttons["training.start"].tap()
    app.buttons["training.startBlank"].tap()
  }

  private func openDirectFoodEditor() {
    app.tabBars.buttons["饮食"].tap()
    app.buttons["nutrition.add"].tap()
  }

  private func revealFoodRow(_ row: XCUIElement) {
    // XCTest's implicit scroll can finish after its tap coordinates were computed.
    // Materialize the complete row above the floating tab bar before any gesture.
    for _ in 0..<4 {
      if row.isHittable && row.frame.maxY < app.tabBars.firstMatch.frame.minY - 8 { break }
      app.swipeUp()
    }
    XCTAssertTrue(row.isHittable)
    XCTAssertLessThan(row.frame.maxY, app.tabBars.firstMatch.frame.minY - 8)
  }

  private func reveal(_ element: XCUIElement) {
    for _ in 0..<8 {
      if element.exists && element.isHittable { return }
      app.swipeUp()
    }
  }

  private func replaceText(in field: XCUIElement, with value: String) {
    reveal(field)
    UITestTextInput.replace(field, with: value, in: app)
  }
}

enum UITestTextInput {
  static func replace(_ field: XCUIElement, with value: String, in app: XCUIApplication) {
    XCTAssertTrue(field.waitForExistence(timeout: 3))
    let visible = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in field.exists && field.isHittable }, object: nil)
    XCTAssertEqual(
      XCTWaiter.wait(for: [visible], timeout: 5), .completed,
      "Input field must be visible: \(field.identifier)")
    field.tap()
    // hasFocus describes system focus, not the iOS text-input first responder.
    // Wait for the keyboard after a center tap; typeText and read-back verify the target.
    let keyboard = app.keyboards.firstMatch
    if !keyboard.waitForExistence(timeout: 3) {
      // Reopened searchable sheets can finish presenting before acquiring a text responder.
      // Reacquire the still-visible field once, then require the keyboard and exact read-back.
      XCTAssertTrue(field.isHittable, "Input field moved before focus: \(field.identifier)")
      field.tap()
    }
    guard keyboard.waitForExistence(timeout: 5) else {
      XCTFail("Keyboard did not appear for input: \(field.identifier)")
      return
    }
    // Search bars stay pinned beside the keyboard; scrolling their results cannot move the field.
    // Only form rows need to move above a keyboard accessory before text selection.
    if field.elementType != .searchField {
      var didScroll = false
      for _ in 0..<4 {
        let safeBottom = app.keyboards.firstMatch.frame.minY - 80
        if field.frame.maxY < safeBottom { break }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: app.frame.width * 0.15, dy: safeBottom - 20))
        let end = origin.withOffset(CGVector(dx: app.frame.width * 0.15, dy: safeBottom - 220))
        start.press(forDuration: 0.05, thenDragTo: end)
        didScroll = true
      }
      // A second tap on an already focused empty field opens AutoFill's editing menu.
      // Reacquire focus only when scrolling actually moved this form row.
      if didScroll {
        field.tap()
      }
    }

    let current = field.value as? String ?? ""
    // Numeric SwiftUI fields can expose "0" as both their value and placeholder.
    // It is still a real bound value and must be selected before replacement.
    let hasNumericValue = Double(current.replacingOccurrences(of: ",", with: "")) != nil
    if !current.isEmpty && (current != field.placeholderValue || hasNumericValue) {
      field.press(forDuration: 1.1)
      let selectAll = app.buttons.matching(
        NSPredicate(format: "label IN {'Select All', '全选'}")
      ).firstMatch
      let menuSelectAll = app.menuItems.matching(
        NSPredicate(format: "label IN {'Select All', '全选'}")
      ).firstMatch
      if selectAll.waitForExistence(timeout: 2) {
        selectAll.tap()
      } else if menuSelectAll.waitForExistence(timeout: 2) {
        menuSelectAll.tap()
      } else {
        XCTFail("Select All is unavailable for nonempty field: \(field.identifier)")
        return
      }
    }

    field.typeText(value)
    if field.elementType == .searchField {
      // A searchable sheet can replace its AX search element while filtering. Query the
      // complete value afresh instead of polling a snapshot captured midway through typing.
      let entered = app.searchFields.matching(NSPredicate(format: "value == %@", value)).firstMatch
      XCTAssertTrue(entered.waitForExistence(timeout: 10), "Search input must equal: \(value)")
      return
    }
    var actual = field.value as? String ?? ""
    func matchesExpected(_ text: String) -> Bool {
      if let expected = Double(value),
        let observed = Double(text.replacingOccurrences(of: ",", with: ""))
      {
        return abs(observed - expected) <= 0.000_001
      }
      return text == value
    }
    if !matchesExpected(actual) {
      // Event synthesis can finish before the bound value/AX snapshot settles. Observe only:
      // never append a missing suffix, retype the phrase, or accept a prefix as success.
      let started = Date()
      var observations = ["0s: \(actual)"]
      let readBack = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          let observed = field.value as? String ?? ""
          if observed != actual && observations.count < 32 {
            observations.append("\(Date().timeIntervalSince(started))s: \(observed)")
          }
          actual = observed
          return matchesExpected(actual)
        }, object: nil)
      _ = XCTWaiter.wait(for: [readBack], timeout: 10)
      // The outer waiter can interrupt an in-flight AX query and leave its cached value empty.
      // Read independently after observation ends before asserting the field's current value.
      actual = field.value as? String ?? ""
      if !matchesExpected(actual) {
        XCTContext.runActivity(named: "Text input did not reach the expected value") { activity in
          let trace = XCTAttachment(
            string:
              "expected: \(value)\nactual: \(actual)\nobservations: \(observations)\nfield: \(field.identifier), \(field.frame), hittable=\(field.isHittable)\nkeyboard present: \(keyboard.exists)"
          )
          trace.lifetime = .keepAlways
          activity.add(trace)
          let screenshot = XCTAttachment(screenshot: app.screenshot())
          screenshot.lifetime = .keepAlways
          activity.add(screenshot)
        }
      }
    }
    if let expectedNumber = Double(value),
      let actualNumber = Double(actual.replacingOccurrences(of: ",", with: ""))
    {
      XCTAssertEqual(actualNumber, expectedNumber, accuracy: 0.000_001)
    } else {
      XCTAssertEqual(actual, value)
    }
    if app.buttons["收起键盘"].exists {
      app.buttons["收起键盘"].tap()
      XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    } else if app.keyboards.count > 0 && app.buttons["完成"].exists,
      field.identifier.hasPrefix("nutrition.") || field.identifier.hasPrefix("foodPreset.")
        || field.identifier.hasPrefix("mealTemplate.")
    {
      app.buttons["完成"].firstMatch.tap()
      XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }
  }
}
