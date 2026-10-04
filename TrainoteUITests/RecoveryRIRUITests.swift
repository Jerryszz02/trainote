import XCTest

final class RecoveryRIRUITests: XCTestCase {
  func testSelectingRecoveryMuscleRevealsDetailFrom3DAndList() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
    app.launch()
    app.tabBars.buttons["恢复"].tap()
    let chest3D = app.buttons["bodyMap.label.chest"]
    XCTAssertTrue(chest3D.waitForExistence(timeout: 5))
    chest3D.tap()
    let detailAction = app.buttons["更新这块肌群的体感"]
    waitUntilHittable(detailAction)
    let listToggle = app.buttons["bodyMap.toggleList"]
    revealAbove(listToggle, in: app)
    listToggle.tap()
    let chestRow = app.buttons["bodyMap.row.chest"]
    revealAbove(chestRow, in: app)
    chestRow.tap()
    waitUntilHittable(detailAction)
    revealAbove(chestRow, in: app)
    chestRow.tap()
    waitUntilHittable(detailAction)
  }

  func testAccessibilityTextListSelectionKeepsMuscleDetailReachable() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-ui-testing",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
      "-ui-testing-dark",
    ]
    app.launch()
    app.tabBars.buttons["恢复"].tap()
    XCTAssertTrue(app.staticTexts["bodyMap.fallback"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["bodyMap.toggleList"].exists)
    let chestRow = app.buttons["bodyMap.row.chest"]
    let detailRegion = app.descendants(matching: .any)["recovery.detail.chest"].firstMatch
    let chestTitles = app.staticTexts.matching(NSPredicate(format: "label == %@", "胸部"))
    let detailAction = app.buttons["更新这块肌群的体感"]
    func capture(_ name: String) {
      let attachment = XCTAttachment(screenshot: app.screenshot())
      attachment.name = name
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    func assertDetailReachable() {
      XCTAssertTrue(detailRegion.waitForExistence(timeout: 5), app.debugDescription)
      let visibleDetailTitle = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          chestTitles.allElementsBoundByIndex.contains {
            $0.isHittable && $0.frame.minY > chestRow.frame.maxY
          }
        }, object: nil)
      XCTAssertEqual(
        XCTWaiter.wait(for: [visibleDetailTitle], timeout: 5), .completed,
        app.debugDescription)
      // A full swipe can jump over this button on the compact screen at Accessibility XXXL.
      for _ in 0..<12 where !detailAction.isHittable {
        let targetIsAbove = detailAction.frame.midY < app.frame.midY
        let start = app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: targetIsAbove ? 0.35 : 0.65))
        let end = app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: targetIsAbove ? 0.65 : 0.35))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
      }
      XCTAssertTrue(detailAction.isHittable, app.debugDescription)
    }
    revealBelow(chestRow, in: app)
    chestRow.tap()
    capture("大字号首次选择胸部详情")
    assertDetailReachable()
    revealAbove(chestRow, in: app)
    chestRow.tap()
    capture("大字号再次选择胸部详情")
    assertDetailReachable()
  }

  func testAdviceShowsTiredReasonSeparatePainRestrictionAndOpensCheckIn() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
    app.launch()
    app.buttons["today.library"].tap()
    app.buttons["训练模板"].tap()
    app.buttons["routine.create"].tap()
    app.buttons["routine.addExercise"].tap()
    UITestTextInput.replace(app.searchFields.firstMatch, with: "barbell bench press", in: app)
    app.buttons["exercisePicker.item.0025"].tap()
    app.buttons["routine.save"].tap()

    app.tabBars.buttons["恢复"].tap()
    app.buttons["bodyMap.toggleList"].tap()
    app.buttons["bodyMap.row.chest"].tap()
    let feedback = app.buttons["更新这块肌群的体感"]
    waitUntilHittable(feedback)
    feedback.tap()
    let feeling = app.buttons["recovery.checkIn.feeling"]
    feeling.press(forDuration: 0.15)
    app.buttons["疲惫"].tap()
    app.buttons["胸部"].tap()
    let pain = app.buttons["recovery.pain.chest"]
    revealBelow(pain, in: app)
    pain.tap()
    app.buttons["有"].tap()
    app.buttons["recovery.checkIn.save"].tap()

    app.buttons["recovery.trainingAdvice"].tap()
    app.buttons["advice.selectedRoutine"].tap()
    app.buttons["新训练模板"].tap()
    app.buttons["advice.refresh"].tap()
    let tiredReason = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "你今天记录了整体疲惫")
    ).firstMatch
    XCTAssertTrue(tiredReason.waitForExistence(timeout: 5), app.debugDescription)
    let restriction = app.staticTexts.matching(
      NSPredicate(
        format: "label CONTAINS %@ AND label CONTAINS %@",
        "另有疼痛或活动受限记录", "胸部")
    ).firstMatch
    XCTAssertTrue(restriction.waitForExistence(timeout: 5), app.debugDescription)
    let editCheckIn = app.buttons["advice.editCheckIn"].firstMatch
    revealBelow(editCheckIn, in: app)
    editCheckIn.tap()
    XCTAssertTrue(app.navigationBars["十秒体感"].waitForExistence(timeout: 3))
    XCTAssertTrue(feeling.label.contains("疲惫"))
    feeling.press(forDuration: 0.15)
    app.buttons["好"].tap()
    app.buttons["recovery.checkIn.save"].tap()
    let painReason = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "已记录疼痛或活动受限")
    ).firstMatch
    XCTAssertTrue(painReason.waitForExistence(timeout: 5), app.debugDescription)
  }

  func testAdviceOffersExistingWorkoutBeforeAnotherAdoption() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
    app.launch()
    app.tabBars.buttons["训练"].tap()
    app.buttons["training.start"].tap()
    app.buttons["training.startBlank"].tap()
    app.tabBars.buttons["恢复"].tap()
    app.buttons["recovery.trainingAdvice"].tap()
    let resume = app.buttons["advice.continueWorkout"]
    XCTAssertTrue(resume.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["advice.start.keepPlan"].exists)
    resume.tap()
    XCTAssertTrue(app.navigationBars["进行中"].waitForExistence(timeout: 5))
  }

  private func waitUntilHittable(_ element: XCUIElement) {
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in element.exists && element.isHittable }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
  }

  private func revealAbove(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<8 where !element.isHittable { app.swipeDown() }
    XCTAssertTrue(element.isHittable)
  }

  private func revealBelow(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<8 where !element.isHittable { app.swipeUp() }
    XCTAssertTrue(element.isHittable)
  }

  func testRIRAndRoleSurviveHistoricalEditAndNewTrainingResetsRIR() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
    app.launch()
    app.tabBars.buttons["训练"].tap()
    app.buttons["training.start"].tap()
    app.buttons["training.startBlank"].tap()
    app.buttons["workout.addExercise"].tap()
    let search = app.searchFields.firstMatch
    UITestTextInput.replace(search, with: "barbell bench press", in: app)
    app.buttons["exercisePicker.item.0025"].tap()
    func control(_ prefix: String) -> XCUIElement {
      app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }
    func reveal(_ element: XCUIElement) {
      for _ in 0..<6 {
        if element.isHittable { return }
        app.swipeUp()
      }
    }
    let role = control("strengthSet.role.")
    XCTAssertTrue(role.waitForExistence(timeout: 3))
    XCTAssertTrue(role.label.contains("工作组"))
    let rir = control("strengthSet.rir.")
    reveal(rir)
    rir.tap()
    app.buttons["1 次"].tap()
    XCTAssertTrue(rir.label.contains("1 次"))
    role.tap()
    app.buttons["热身组"].tap()
    let complete = control("strengthSet.complete.")
    complete.tap()
    app.buttons["workout.finish"].tap()
    let row = app.buttons.matching(
      NSPredicate(format: "label CONTAINS '已完成' AND label CONTAINS '自由训练'")
    ).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 3))
    row.tap()
    app.buttons["training.edit"].tap()
    reveal(rir)
    XCTAssertTrue(rir.label.contains("1 次"))
    XCTAssertTrue(role.label.contains("热身组"))
    app.buttons["workout.edit.cancel"].tap()
    app.buttons["training.repeat"].tap()
    reveal(rir)
    XCTAssertTrue(rir.label.contains("未记录"))
    XCTAssertTrue(role.label.contains("热身组"))
    XCTAssertFalse(complete.label.contains("已完成"))
    let image = XCTAttachment(screenshot: app.screenshot())
    image.name = "Repeated workout clears RIR"
    image.lifetime = .keepAlways
    add(image)
  }
}
