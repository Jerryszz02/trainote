import XCTest

final class FirstUseNoticeUITests: XCTestCase {
  func testDeclineThenAgreeAndRestartDoesNotReopenNotice() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing", "-ui-testing-first-use", "-appearance.language", "en"]
    app.launchEnvironment["TRAINOTE_UI_NOTICE_ID"] = UUID().uuidString
    app.launch()
    XCTAssertTrue(app.buttons["notice.agree"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.tabBars.firstMatch.exists)
    app.buttons["notice.notNow"].tap()
    XCTAssertTrue(app.buttons["notice.agree"].exists)
    XCTAssertFalse(app.tabBars.firstMatch.exists)
    app.buttons["notice.agree"].tap()
    XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
    app.terminate()
    app.launch()
    XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["notice.agree"].exists)
  }

  func testChineseNoticeAndWithdrawalReturnToRestrictedPage() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing", "-ui-testing-first-use", "-appearance.language", "zh-Hans"]
    app.launchEnvironment["TRAINOTE_UI_NOTICE_ID"] = UUID().uuidString
    app.launch()
    XCTAssertTrue(app.buttons["notice.agree"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["notice.agree"].label, "同意并继续")
    app.buttons["notice.agree"].tap()
    XCTAssertTrue(app.buttons["today.settings"].waitForExistence(timeout: 5))
    app.buttons["today.settings"].tap()
    let withdraw = app.buttons["settings.withdrawNotice"]
    for _ in 0..<5 where !withdraw.isHittable { app.swipeUp() }
    XCTAssertTrue(withdraw.isHittable)
    withdraw.tap()
    app.sheets.buttons["撤回须知确认"].tap()
    XCTAssertTrue(app.buttons["notice.agree"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.tabBars.firstMatch.exists)
    app.terminate()
    app.launch()
    XCTAssertTrue(app.buttons["notice.agree"].waitForExistence(timeout: 5))
  }
}
