import XCTest

final class TrendAdoptionUITests: XCTestCase {
  private var app: XCUIApplication!
  private let appLocale = Locale(identifier: "zh_Hans_CN")

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = [
      "-ui-testing", "-ui-testing-legacy-goal",
      "-AppleLanguages", "(zh-Hans)", "-AppleLocale", appLocale.identifier,
    ]
    app.launchEnvironment["TZ"] = TimeZone.current.identifier
    app.launch()
  }

  func testRealInitialProposalAdoptionAndUndoRestoreLegacyGoal() {
    app.tabBars.buttons["趋势"].tap()
    let enable = app.buttons["trend.enableSuggestions"]
    XCTAssertTrue(enable.waitForExistence(timeout: 5), "升级态应先显示显式启用入口")
    enable.tap()

    let profile = app.buttons["trend.completeProfile"]
    reveal(profile)
    XCTAssertTrue(profile.isHittable, "缺资料提示旁应能直接打开身体资料表单")
    profile.tap()
    UITestTextInput.replace(app.textFields["trend.profile.height"], with: "175", in: app)
    UITestTextInput.replace(app.textFields["trend.profile.age"], with: "30", in: app)
    choose("公式使用的生理性别参数", option: "男性参数")
    choose("活动水平", option: "中等活动")
    choose("每周训练天数", option: "3 天")
    choose("目标方向", option: "减脂")
    choose("通用建议适用条件", option: "成年日常健身，无特殊营养需求")
    app.buttons["trend.profile.save"].tap()
    XCTAssertTrue(app.navigationBars["趋势分析"].waitForExistence(timeout: 5), "资料保存后应回到趋势页")

    let addWeight = app.buttons["trend.addWeight"]
    XCTAssertTrue(addWeight.waitForExistence(timeout: 3))
    addWeight.tap()
    UITestTextInput.replace(app.textFields["trend.weight.kilograms"], with: "70", in: app)
    app.buttons["trend.weight.save"].tap()
    XCTAssertTrue(app.navigationBars["趋势分析"].waitForExistence(timeout: 5), "体重保存后应回到趋势页")
    let adopt = app.buttons["trend.adopt"]
    reveal(adopt)
    XCTAssertTrue(adopt.waitForExistence(timeout: 5), "真实资料与近期体重应产生初始目标建议")
    XCTAssertTrue(adopt.isEnabled, "初始建议应可由用户显式采用")
    let oldTarget = targetRow(prefix: "当前", calories: 2000)
    reveal(oldTarget)
    XCTAssertTrue(oldTarget.exists, "采用前应保留旧版 2000 kcal 目标")
    let proposal = targetRow(prefix: "建议", calories: 2242)
    reveal(proposal)
    XCTAssertTrue(proposal.exists, "建议应来自实际趋势计算")
    let adjustment = app.staticTexts["热量调整 +242 kcal"]
    reveal(adjustment)
    XCTAssertTrue(adjustment.isHittable, "调整量应等于展示目标之差：2242 − 2000 = 242")
    capture("旧目标与真实初始建议")

    reveal(adopt)
    adopt.tap()
    let adopted = targetRow(prefix: "当前", calories: 2242)
    reveal(adopted)
    XCTAssertTrue(adopted.waitForExistence(timeout: 5), "采用后当前目标应切换为建议值")
    app.tabBars.buttons["今日"].tap()
    let adoptedTodayCalories = app.descendants(matching: .any)["today.nutrient.calories"].firstMatch
    reveal(adoptedTodayCalories)
    XCTAssertTrue(adoptedTodayCalories.label.contains("目标 2,242")
      || adoptedTodayCalories.label.contains("目标 2242"), "今日目标与趋势建议应按同一整数精度显示")
    app.tabBars.buttons["趋势"].tap()
    let adoptedHistory = app.staticTexts["已采用建议"]
    reveal(adoptedHistory)
    XCTAssertTrue(adoptedHistory.exists, "采用应写入建议目标历史")
    let undo = app.buttons["trend.undo"]
    reveal(undo)
    XCTAssertTrue(undo.isHittable, "有旧目标时应提供撤销入口")
    capture("已采用建议与可撤销历史")

    let undoRequestedAt = Date()
    undo.tap()
    let restored = targetRow(prefix: "当前", calories: 2000)
    reveal(restored)
    XCTAssertTrue(restored.waitForExistence(timeout: 5), "撤销应恢复旧版 2000 kcal 目标")
    let reversedHistory = app.staticTexts["已撤销"]
    reveal(reversedHistory)
    XCTAssertTrue(reversedHistory.exists, "建议历史应标记为已撤销")
    let hold = app.staticTexts["trend.hold"]
    revealAbove(hold)
    XCTAssertEqual(hold.label, "已暂停调整，当前目标保持不变。", "撤销后的历史应进入暂停状态")
    XCTAssertFalse(app.buttons["trend.adopt"].exists, "暂停期间不应再次采用已撤销的建议")
    let review = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "下次复核")
    ).firstMatch
    reveal(review)
    XCTAssertTrue(review.exists, "撤销后应显示下次复核日期")
    // The app's development language is Chinese; the CI test runner's is English.
    // Compare the real seven-day date using the app's explicit locale and local time zone.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let expectedReview = calendar.date(byAdding: .day, value: 7, to: undoRequestedAt)!
      .formatted(
        Date.FormatStyle(
          date: .abbreviated, time: .omitted, locale: appLocale,
          calendar: calendar, timeZone: calendar.timeZone))
    XCTAssertTrue(
      app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@", expectedReview)
      ).firstMatch.exists,
      "下次复核应为本地七天后：\(expectedReview)")
    let mode = app.buttons["trend.goalMode"]
    reveal(mode)
    XCTAssertTrue(mode.label.contains("建议后采用"), "撤销应保留用户选择的建议模式")
    capture("撤销后旧目标与暂停状态")

    app.tabBars.buttons["今日"].tap()
    let todayCalories = app.descendants(matching: .any)["today.nutrient.calories"].firstMatch
    reveal(todayCalories)
    XCTAssertTrue(todayCalories.waitForExistence(timeout: 5))
    XCTAssertTrue(
      todayCalories.label.contains("目标 2,000") || todayCalories.label.contains("目标 2000"),
      "今日页应读到撤销后恢复的 2000 kcal 目标")
    capture("今日页已恢复旧目标")
  }

  func testNutritionPageConfirmsTodayWhileTrendWindowEndsYesterday() {
    app.tabBars.buttons["饮食"].tap()
    let confirm = app.buttons["nutrition.confirmDiet"]
    reveal(confirm)
    XCTAssertTrue(confirm.isHittable)
    confirm.tap()
    app.buttons["确认当天没有摄入，标记完整"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["nutrition.dietComplete"].firstMatch
      .waitForExistence(timeout: 3))
    app.tabBars.buttons["趋势"].tap()
    let enable = app.buttons["trend.enableSuggestions"]
    if enable.exists { enable.tap() }
    let window = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "截至昨天的 14 天")
    ).firstMatch
    reveal(window)
    XCTAssertTrue(window.exists)
    let pastCount = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "0 / 14 天已确认")
    ).firstMatch
    XCTAssertTrue(pastCount.exists, "今天的确认不应计入截至昨天的 14 天")
    app.tabBars.buttons["饮食"].tap()
    app.buttons["nutrition.add"].tap()
    app.buttons["nutrition.add.direct"].tap()
    UITestTextInput.replace(app.textFields["nutrition.entry.name"], with: "回归测试食物", in: app)
    app.buttons["nutrition.entry.save"].tap()
    let reconfirm = app.buttons["nutrition.confirmDiet"]
    reveal(reconfirm)
    XCTAssertTrue(reconfirm.waitForExistence(timeout: 3), "补记饮食后，先前的完整确认应失效")
  }

  private func targetRow(prefix: String, calories: Int) -> XCUIElement {
    let compact = "\(prefix) \(calories) kcal"
    let grouped = "\(prefix) \(calories.formatted()) kcal"
    return app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", compact, grouped)
    ).firstMatch
  }

  private func choose(_ label: String, option: String) {
    let picker = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", label)
    ).firstMatch
    reveal(picker)
    XCTAssertTrue(picker.isHittable, "应能选择：\(label)")
    picker.tap()
    let choice = app.buttons[option]
    XCTAssertTrue(choice.waitForExistence(timeout: 3), "应有选项：\(option)")
    choice.tap()
  }

  private func reveal(_ element: XCUIElement) {
    for _ in 0..<12 {
      if element.isHittable { return }
      if element.exists && element.frame.midY < app.frame.midY {
        app.swipeDown()
      } else {
        app.swipeUp()
      }
    }
  }

  private func revealAbove(_ element: XCUIElement) {
    for _ in 0..<8 {
      if element.isHittable { return }
      app.swipeDown()
    }
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
