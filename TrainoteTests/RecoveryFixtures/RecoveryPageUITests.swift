#if RECOVERY_PREVIEW_TESTS
  import XCTest

  final class RecoveryPageUITests: XCTestCase {
    let app = XCUIApplication()
    override func setUpWithError() throws { continueAfterFailure = false }
    func reveal(_ element: XCUIElement) {
      for _ in 0..<8 {
        if element.isHittable { return }
        app.swipeUp()
      }
    }
    func capture(_ name: String) {
      let image = XCTAttachment(screenshot: app.screenshot())
      image.name = name
      image.lifetime = .keepAlways
      add(image)
    }
    func testRenderedBodySelectionFeedbackSaveAndSkip() {
      app.launch()
      XCTAssertTrue(app.otherElements["bodyMap.scene"].waitForExistence(timeout: 5))
      let chest = app.buttons["bodyMap.label.chest"]
      XCTAssertTrue(chest.waitForExistence(timeout: 5))
      capture("Recovery populated body map")
      chest.tap()
      let feedback = app.buttons["更新这块肌群的体感"]
      reveal(feedback)
      feedback.tap()
      XCTAssertTrue(app.navigationBars["十秒体感"].waitForExistence(timeout: 3))
      app.buttons["胸部"].tap()
      let pain = app.buttons["recovery.pain.chest"]
      reveal(pain)
      pain.tap()
      app.buttons["有"].tap()
      app.buttons["recovery.checkIn.save"].tap()
      XCTAssertTrue(app.navigationBars["恢复分析"].waitForExistence(timeout: 3))
      let warning = app.staticTexts["已标记疼痛：相关训练暂不列入建议"]
      reveal(warning)
      XCTAssertTrue(warning.exists)
      capture("Pain overrides readiness")
      reveal(feedback)
      feedback.tap()
      app.buttons["胸部"].tap()
      XCTAssertTrue(pain.label.contains("有"))
      pain.tap()
      app.buttons["无"].tap()
      app.buttons["recovery.checkIn.skip"].tap()
      reveal(warning)
      XCTAssertTrue(warning.exists)
      reveal(feedback)
      feedback.tap()
      app.buttons["胸部"].tap()
      XCTAssertTrue(pain.label.contains("有"))
    }
    func testClearingTheOnlyFeelingPersistsAndSkipDoesNotRestoreIt() {
      app.launchArguments = ["-fixture-empty"]
      app.launch()
      let open = app.buttons["recovery.checkIn.open"]
      reveal(open)
      open.tap()
      let feeling = app.buttons["recovery.checkIn.feeling"]
      feeling.tap()
      app.buttons["疲惫"].tap()
      app.buttons["recovery.checkIn.save"].tap()
      reveal(open)
      open.tap()
      XCTAssertTrue(feeling.label.contains("疲惫"))
      feeling.tap()
      app.buttons["未回答"].tap()
      app.buttons["recovery.checkIn.save"].tap()
      reveal(open)
      open.tap()
      XCTAssertTrue(feeling.label.contains("未回答"))
      feeling.tap()
      app.buttons["疲惫"].tap()
      app.buttons["recovery.checkIn.skip"].tap()
      reveal(open)
      open.tap()
      XCTAssertTrue(feeling.label.contains("未回答"))
    }

    func testEmptyRecordingIsUnknownAndCheckInCanBeSkipped() {
      app.launchArguments = ["-fixture-empty"]
      app.launch()
      XCTAssertTrue(app.staticTexts["待建立记录"].waitForExistence(timeout: 5))
      let button = app.buttons["recovery.checkIn.open"]
      reveal(button)
      button.tap()
      app.buttons["recovery.checkIn.skip"].tap()
      XCTAssertTrue(app.navigationBars["恢复分析"].waitForExistence(timeout: 3))
      capture("Empty recovery remains usable after skip")
    }
  }
#endif
