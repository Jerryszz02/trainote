import XCTest

final class HealthIntegrationUITests: XCTestCase {
  private var app: XCUIApplication!
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
    app.buttons["today.settings"].tap()
    XCTAssertTrue(app.buttons["每日营养目标"].waitForExistence(timeout: 3))
    app.buttons["每日营养目标"].tap()
    XCTAssertTrue(app.buttons["goal.save"].exists)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    reveal(app.buttons["backup.export"])
    XCTAssertTrue(app.buttons["backup.export"].isHittable)
    XCTAssertTrue(app.buttons["backup.import"].exists)
  }

  func testDisconnectConfirmationAndOfflineHelp() {
    app.buttons["today.settings"].tap()
    app.buttons["settings.disconnectHealth"].tap()
    app.buttons["断开并删除"].tap()
    XCTAssertTrue(app.staticTexts["已断开并删除健康导入数据及相关报告。手动记录已保留。"].waitForExistence(timeout: 3))
    reveal(app.buttons["settings.healthHelp"])
    app.buttons["settings.healthHelp"].tap()
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
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
    field.press(forDuration: 1.1)
    let selectAll = app.buttons.matching(NSPredicate(format: "label IN {'Select All', '全选'}"))
      .firstMatch
    let menuSelectAll = app.menuItems.matching(NSPredicate(format: "label IN {'Select All', '全选'}"))
      .firstMatch
    if selectAll.waitForExistence(timeout: 1) {
      selectAll.tap()
    } else if menuSelectAll.exists {
      menuSelectAll.tap()
    } else {
      field.doubleTap()
    }
    field.typeText("2100")
    XCTAssertEqual(
      Double((field.value as? String ?? "").replacingOccurrences(of: ",", with: "")), 2100)
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
    let openToday = app.buttons["today.checkIn.open"]
    openToday.tap()
    let feeling = app.buttons["recovery.checkIn.feeling"]
    feeling.tap()
    app.buttons["疲惫"].tap()
    app.buttons["recovery.checkIn.save"].tap()
    XCTAssertTrue(app.buttons["today.recommendation"].label.contains("疲惫"))
    app.buttons["today.recommendation"].tap()
    XCTAssertTrue(app.navigationBars["恢复分析"].waitForExistence(timeout: 3))
    let openRecovery = app.buttons["recovery.checkIn.open"]
    reveal(openRecovery)
    openRecovery.tap()
    XCTAssertTrue(feeling.label.contains("疲惫"))
    feeling.tap()
    app.buttons["好"].tap()
    app.buttons["recovery.checkIn.skip"].tap()
    app.tabBars.buttons["今日"].tap()
    XCTAssertTrue(app.buttons["today.recommendation"].label.contains("疲惫"))
    openToday.tap()
    XCTAssertTrue(feeling.label.contains("疲惫"))
    feeling.tap()
    app.buttons["未回答"].tap()
    app.buttons["recovery.checkIn.save"].tap()
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
