import XCTest

final class HealthIntegrationUITests: XCTestCase {
  private var app: XCUIApplication!
  private var capturedFailureDiagnostics = false

  override func record(_ issue: XCTIssue) {
    let isHealthControlTest =
      name.contains("testDisconnectConfirmationAndOfflineHelp")
      || name.contains("testTodayCheckInUpdatesRecoveryAndSkipPreservesSavedFeeling")
    if isHealthControlTest && !capturedFailureDiagnostics, let app {
      capturedFailureDiagnostics = true
      capture("健康控件失败时画面")
      let hierarchy = XCTAttachment(string: app.debugDescription)
      hierarchy.name = "健康控件失败时完整控件树"
      hierarchy.lifetime = .keepAlways
      add(hierarchy)
      let nativeMenu = XCTAttachment(
        string: """
          menus=\(app.menus.count)
          tiredInMenus=\(app.menus.buttons.matching(identifier: "疲惫").count)
          tiredButtons=\(app.buttons.matching(identifier: "疲惫").count)
          operationError=\(app.alerts["操作未完成"].exists)
          """)
      nativeMenu.name = "健康控件失败时原生菜单查询"
      nativeMenu.lifetime = .keepAlways
      add(nativeMenu)
    }
    super.record(issue)
  }

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
    app.launch()
  }

  func testLocalOnlyOnboardingAndUnconfiguredAIDoNotBlockRecording() {
    app.terminate()
    app.launchArguments += ["-health-onboarding"]
    app.launch()
    XCTAssertTrue(app.buttons["health.localOnly"].waitForExistence(timeout: 5))
    capture("分项数据引导")
    app.buttons["health.aiInfo"].tap()
    XCTAssertTrue(app.staticTexts["health.aiUnavailable"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["health.aiConsent"].exists)
    capture("AI未配置说明")
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["health.localOnly"].tap()
    XCTAssertTrue(app.tabBars.buttons["今日"].waitForExistence(timeout: 3))
    app.buttons["today.startWorkout"].tap()
    XCTAssertTrue(app.buttons["training.startBlank"].waitForExistence(timeout: 3))
  }

  func testAllLibraryEntrancesChooseTheirOwnSection() {
    app.buttons["today.library"].tap()
    XCTAssertTrue(app.navigationBars["资料库"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.segmentedControls.buttons["动作"].isSelected)
    app.tabBars.buttons["训练"].tap()
    app.buttons["training.routines"].tap()
    XCTAssertTrue(app.segmentedControls.buttons["训练模板"].isSelected)
    XCTAssertTrue(app.buttons["routine.create"].exists)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["training.exercises"].tap()
    XCTAssertTrue(app.segmentedControls.buttons["动作"].isSelected)
    app.tabBars.buttons["饮食"].tap()
    app.buttons["nutrition.library"].tap()
    XCTAssertTrue(app.segmentedControls.buttons["饮食"].isSelected)
    XCTAssertTrue(app.segmentedControls.buttons["常用食物"].exists)
    XCTAssertTrue(app.segmentedControls.buttons["固定餐"].exists)
  }

  func testTodaySuggestionCanOpenTemplateSelectionAndOldSettingsRemain() {
    app.buttons["today.recommendation"].tap()
    XCTAssertTrue(app.buttons["routine.create"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.segmentedControls.buttons["训练模板"].isSelected)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    let settings = app.buttons["today.settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 3))
    settings.tap()
    XCTAssertTrue(app.buttons["每日营养目标"].waitForExistence(timeout: 3))
    app.buttons["每日营养目标"].tap()
    XCTAssertTrue(app.navigationBars["营养目标"].waitForExistence(timeout: 3))
    let save = app.buttons["goal.save"]
    XCTAssertTrue(save.waitForExistence(timeout: 3))
    let saveReady = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in save.isHittable }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [saveReady], timeout: 3), .completed)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 3))
    reveal(app.buttons["backup.export"])
    XCTAssertTrue(app.buttons["backup.export"].isHittable)
    XCTAssertTrue(app.buttons["backup.import"].exists)
  }

  func testDisconnectConfirmationAndOfflineHelp() {
    app.buttons["today.settings"].tap()
    XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 3))
    let disconnect = app.buttons["settings.disconnectHealth"]
    reveal(disconnect)
    disconnect.tap()
    let confirmation = app.buttons["断开并删除"]
    XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
    XCTAssertTrue(confirmation.isHittable)
    // CI dismissed this popover after a 50 ms tap without producing an operation result.
    // Touch it once, then require the success message; never replay a deletion on timeout.
    confirmation.press(forDuration: 0.15)
    XCTAssertTrue(confirmation.waitForNonExistence(timeout: 3))

    // The result is a dynamic Form row directly below help. Locate this stable neighbor first;
    // searching for an unmaterialized row by repeatedly swiping can scroll past it entirely.
    let help = app.buttons["settings.healthHelp"]
    reveal(help)
    if help.frame.midY > app.frame.height * 0.55 {
      let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.65))
      let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.35))
      start.press(forDuration: 0.05, thenDragTo: end)
    }
    let status = app.staticTexts["settings.healthStatus"]
    let result = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        status.exists || self.app.alerts["操作未完成"].exists
      }, object: nil)
    XCTAssertEqual(
      XCTWaiter.wait(for: [result], timeout: 10), .completed,
      "确认后应出现操作结果，按钮重新可点不代表成功。")
    XCTAssertFalse(app.alerts["操作未完成"].exists, "健康断开与删除未成功")
    reveal(status)
    XCTAssertTrue(status.isHittable)
    XCTAssertEqual(status.label, "已断开并删除健康导入数据及相关报告。手动记录已保留。")
    reveal(help)
    help.tap()
    XCTAssertTrue(app.navigationBars["方法与数据使用"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["分析方法与适用范围"].exists)
  }

  func testManualTargetChangesAreVisibleAfterSettingsCloses() {
    app.buttons["today.settings"].tap()
    app.buttons["每日营养目标"].tap()
    app.buttons["goal.save"].tap()
    XCTAssertTrue(app.buttons["已保存"].waitForExistence(timeout: 3))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["完成"].tap()
    let card = app.descendants(matching: .any)["today.nutrient.calories"].firstMatch
    reveal(card)
    XCTAssertTrue(card.label.contains("目标 2,000") || card.label.contains("目标 2000"))
    app.buttons["today.settings"].tap()
    app.buttons["每日营养目标"].tap()
    let field = app.textFields["goal.卡路里"]
    reveal(field)
    UITestTextInput.replace(field, with: "2100", in: app)
    app.buttons["goal.save"].tap()
    capture("手动目标再次保存")
    XCTAssertTrue(app.buttons["已保存"].waitForExistence(timeout: 3))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["完成"].tap()
    reveal(card)
    XCTAssertTrue(card.label.contains("目标 2,100") || card.label.contains("目标 2100"))
  }

  func testLargeTextKeepsPrimaryNavigation() {
    app.terminate()
    app.launchArguments += [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
      "-ui-testing-dark",
    ]
    app.launch()
    XCTAssertTrue(app.buttons["today.settings"].waitForExistence(timeout: 3))
    XCTAssertEqual(app.tabBars.buttons.count, 5)
    capture("今日大字号")
    app.buttons["today.library"].tap()
    XCTAssertTrue(app.buttons["library.section"].waitForExistence(timeout: 3))
    capture("资料库大字号")
    app.tabBars.buttons["趋势"].tap()
    XCTAssertTrue(app.navigationBars["趋势分析"].waitForExistence(timeout: 3))
    app.tabBars.buttons["恢复"].tap()
    XCTAssertTrue(app.navigationBars["恢复分析"].waitForExistence(timeout: 3))
  }

  func testTodayCheckInUpdatesRecoveryAndSkipPreservesSavedFeeling() {
    func waitUntilHittable(_ button: XCUIElement) {
      let ready = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in button.exists && button.isHittable }, object: nil)
      XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed)
    }

    let openToday = app.buttons["today.checkIn.open"]
    openToday.tap()
    XCTAssertTrue(app.navigationBars["十秒体感"].waitForExistence(timeout: 3))
    let feeling = app.buttons["recovery.checkIn.feeling"]
    XCTAssertTrue(feeling.waitForExistence(timeout: 3))
    waitUntilHittable(feeling)
    feeling.press(forDuration: 0.15)
    let tired = app.buttons["疲惫"]
    XCTAssertTrue(tired.waitForExistence(timeout: 3), "整体感觉选项未打开")
    waitUntilHittable(tired)
    tired.tap()
    XCTAssertTrue(app.navigationBars["十秒体感"].waitForExistence(timeout: 3))
    app.buttons["recovery.checkIn.save"].tap()
    XCTAssertTrue(app.navigationBars["十秒体感"].waitForNonExistence(timeout: 3))
    XCTAssertTrue(app.buttons["today.recommendation"].label.contains("疲惫"))
    app.buttons["today.recommendation"].tap()
    XCTAssertTrue(app.navigationBars["恢复分析"].waitForExistence(timeout: 3))
    let openRecovery = app.buttons["recovery.checkIn.open"]
    reveal(openRecovery)
    openRecovery.tap()
    XCTAssertTrue(app.navigationBars["十秒体感"].waitForExistence(timeout: 3))
    waitUntilHittable(feeling)
    XCTAssertTrue(feeling.label.contains("疲惫"))
    feeling.press(forDuration: 0.15)
    let good = app.buttons["好"]
    XCTAssertTrue(good.waitForExistence(timeout: 3), "整体感觉选项未打开")
    waitUntilHittable(good)
    good.tap()
    XCTAssertTrue(app.navigationBars["十秒体感"].waitForExistence(timeout: 3))
    app.buttons["recovery.checkIn.skip"].tap()
    XCTAssertTrue(app.navigationBars["十秒体感"].waitForNonExistence(timeout: 3))
    app.tabBars.buttons["今日"].tap()
    XCTAssertTrue(app.buttons["today.recommendation"].label.contains("疲惫"))
    openToday.tap()
    XCTAssertTrue(app.navigationBars["十秒体感"].waitForExistence(timeout: 3))
    waitUntilHittable(feeling)
    XCTAssertTrue(feeling.label.contains("疲惫"))
    feeling.press(forDuration: 0.15)
    let unanswered = app.buttons["未回答"]
    XCTAssertTrue(unanswered.waitForExistence(timeout: 3), "整体感觉选项未打开")
    waitUntilHittable(unanswered)
    unanswered.tap()
    XCTAssertTrue(app.navigationBars["十秒体感"].waitForExistence(timeout: 3))
    app.buttons["recovery.checkIn.save"].tap()
    XCTAssertTrue(app.navigationBars["十秒体感"].waitForNonExistence(timeout: 3))
    XCTAssertFalse(app.buttons["today.recommendation"].label.contains("疲惫"))
  }

  func testRecoveryBodyMapPainConstraintAndBundledMethods() {
    app.tabBars.buttons["恢复"].tap()
    XCTAssertTrue(app.otherElements["bodyMap.scene"].waitForExistence(timeout: 5))
    capture("生产恢复页未知状态")
    app.buttons["bodyMap.toggleList"].tap()
    let chest = app.buttons["bodyMap.row.chest"]
    XCTAssertTrue(chest.waitForExistence(timeout: 5))
    chest.tap()
    let feedback = app.buttons["更新这块肌群的体感"]
    reveal(feedback)
    feedback.tap()
    app.buttons["胸部"].tap()
    let pain = app.buttons["recovery.pain.chest"]
    reveal(pain)
    pain.tap()
    app.buttons["有"].tap()
    app.buttons["recovery.checkIn.save"].tap()
    let warning = app.staticTexts["已标记疼痛：相关训练暂不列入建议"]
    reveal(warning)
    XCTAssertTrue(warning.exists)
    capture("生产恢复页疼痛约束")
    let methods = app.buttons["计算方法与数据使用"]
    reveal(methods)
    methods.tap()
    XCTAssertTrue(app.navigationBars["方法与数据使用"].waitForExistence(timeout: 3))
    reveal(app.staticTexts["恢复指数如何计算"])
    XCTAssertTrue(app.staticTexts["恢复指数如何计算"].exists)
  }

  func testTrendSuggestionsPreserveManualTargetAndSaveManualWeight() {
    app.buttons["today.settings"].tap()
    app.buttons["每日营养目标"].tap()
    app.buttons["goal.save"].tap()
    XCTAssertTrue(app.buttons["已保存"].waitForExistence(timeout: 3))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["完成"].tap()
    app.tabBars.buttons["趋势"].tap()
    XCTAssertTrue(app.buttons["trend.enableSuggestions"].waitForExistence(timeout: 3))
    app.buttons["trend.enableSuggestions"].tap()
    XCTAssertTrue(app.buttons["trend.addWeight"].waitForExistence(timeout: 3))
    let mode = app.buttons["trend.goalMode"]
    reveal(mode)
    XCTAssertTrue(mode.label.contains("建议后采用"))
    app.buttons["trend.addWeight"].tap()
    let field = app.textFields["trend.weight.kilograms"]
    field.tap()
    field.typeText("70")
    app.buttons["trend.weight.save"].tap()
    XCTAssertTrue(app.navigationBars["趋势分析"].waitForExistence(timeout: 3))
    app.swipeDown()
    XCTAssertTrue(app.otherElements["trend.weightChart"].exists)
    capture("真实趋势页手动体重")
    app.tabBars.buttons["今日"].tap()
    let card = app.descendants(matching: .any)["today.nutrient.calories"].firstMatch
    reveal(card)
    XCTAssertTrue(card.label.contains("目标 2,000") || card.label.contains("目标 2000"))
  }

  func testTrendViewOnlyKeepsManualModeAndOpensExistingGoalEditor() {
    app.tabBars.buttons["趋势"].tap()
    app.buttons["trend.continueCurrentMode"].tap()
    let mode = app.buttons["trend.goalMode"]
    reveal(mode)
    XCTAssertTrue(mode.label.contains("手动"))
    let editor = app.buttons["编辑手动营养目标"]
    reveal(editor)
    editor.tap()
    XCTAssertTrue(app.buttons["goal.save"].waitForExistence(timeout: 3))
    app.buttons["goal.save"].tap()
    XCTAssertTrue(app.buttons["已保存"].waitForExistence(timeout: 3))
    app.buttons["完成"].tap()
    reveal(mode)
    XCTAssertTrue(mode.label.contains("手动"))
  }

  private func reveal(_ element: XCUIElement) {
    for _ in 0..<8 {
      if element.isHittable { return }
      app.swipeUp()
    }
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
