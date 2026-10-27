import XCTest

/// Local-only capture suite. Excluded from routine CI; real AI screenshots use the bundled model.
final class StoreScreenshotUITests: XCTestCase {
  private var app: XCUIApplication!
  override func setUpWithError() throws { continueAfterFailure = false }

  func testEnglishCoreScreenshots() { coreScreenshots(language: "en", locale: "en-US") }
  func testChineseCoreScreenshots() { coreScreenshots(language: "zh-Hans", locale: "zh-Hans") }
  func testEnglishOnDeviceAI() { onDeviceScreenshot(language: "en", locale: "en-US") }
  func testChineseOnDeviceAI() { onDeviceScreenshot(language: "zh-Hans", locale: "zh-Hans") }
  func testEnglishFirstUseNotice() { noticeScreenshot(language: "en", locale: "en-US") }
  func testChineseFirstUseNotice() { noticeScreenshot(language: "zh-Hans", locale: "zh-Hans") }

  private func launch(language: String, firstUse: Bool = false) {
    app?.terminate()
    app = XCUIApplication()
    app.launchArguments = ["-ui-testing", "-store-screenshots", "-appearance.language", language,
      "-AppleLanguages", language == "en" ? "(en)" : "(zh-Hans)",
      "-AppleLocale", language == "en" ? "en_US" : "zh_CN"]
    if firstUse { app.launchArguments += ["-ui-testing-first-use"] }
    app.launchEnvironment["TRAINOTE_UI_NOTICE_ID"] = UUID().uuidString
    app.launch()
    XCTAssertTrue(app.staticTexts["store.sampleData"].waitForExistence(timeout: 10))
  }

  private func coreScreenshots(language: String, locale: String) {
    let chinese = language == "zh-Hans"
    launch(language: language)
    XCTAssertTrue(app.buttons["today.startWorkout"].waitForExistence(timeout: 10))
    capture(locale, "01-today")

    app.tabBars.buttons[chinese ? "训练" : "Training"].tap()
    app.buttons["training.activeWorkout"].tap()
    XCTAssertTrue(app.navigationBars[chinese ? "进行中" : "In progress"].waitForExistence(timeout: 5))
    capture(locale, "02-active-workout")

    launch(language: language)
    app.buttons["today.library"].tap()
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 5))
    search.tap()
    search.typeText("barbell bench press")
    let bench = app.buttons["exerciseLibrary.item.0025"]
    XCTAssertTrue(bench.waitForExistence(timeout: 5))
    bench.tap()
    XCTAssertTrue(app.navigationBars[chinese ? "动作详情" : "Exercise details"].waitForExistence(timeout: 5))
    capture(locale, "03-exercise-details")

    launch(language: language)
    app.tabBars.buttons[chinese ? "饮食" : "Nutrition"].tap()
    XCTAssertTrue(app.buttons["nutrition.add"].waitForExistence(timeout: 5))
    capture(locale, "04-nutrition")

    app.tabBars.buttons[chinese ? "趋势" : "Trends"].tap()
    app.buttons["trends.reports"].tap()
    app.buttons["today.weeklyReport"].tap()
    XCTAssertTrue(app.navigationBars[chinese ? "每周回顾" : "Weekly review"].waitForExistence(timeout: 5))
    capture(locale, "05-weekly-review")
  }

  private func onDeviceScreenshot(language: String, locale: String) {
    launch(language: language)
    app.tabBars.buttons[language == "zh-Hans" ? "趋势" : "Trends"].tap()
    app.buttons["trends.reports"].tap()
    app.buttons["today.analysisReports"].tap()
    let generate = app.buttons["reports.generate"]
    XCTAssertTrue(generate.waitForExistence(timeout: 10))
    let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: generate)
    XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
    generate.tap()
    // No mock or fabricated source badge: this must finish the bundled llama.cpp inference.
    let source = app.staticTexts["reports.source.onDevice"]
    XCTAssertTrue(source.waitForExistence(timeout: 90), "The bundled model must produce a validated on-device report")
    if !source.isHittable { app.swipeUp() }
    XCTAssertTrue(source.isHittable)
    capture(locale, "06-on-device-ai")
  }

  private func noticeScreenshot(language: String, locale: String) {
    launch(language: language, firstUse: true)
    XCTAssertTrue(app.buttons["notice.agree"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.tabBars.firstMatch.exists)
    capture(locale, "07-first-use-notice")
  }

  private func capture(_ locale: String, _ page: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "store-\(locale)-\(page)"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
