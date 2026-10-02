import XCTest

final class BodyMapUITests: XCTestCase {
  @MainActor
  func testFrontBackRotationSelectionAndUnknownFixtures() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    let scene = app.otherElements["bodyMap.scene"]
    XCTAssertTrue(scene.waitForExistence(timeout: 10))
    attach("front", app: app)
    app.buttons["bodyMap.label.chest"].tap()
    XCTAssertTrue(app.staticTexts["bodyMap.selection"].label.contains("胸"))
    scene.swipeLeft()
    XCTAssertNotEqual(scene.value as? String, "前面")
    attach("rotated", app: app)
    app.buttons["bodyMap.back"].tap()
    XCTAssertEqual(scene.value as? String, "背面")
    app.buttons["bodyMap.label.glutes"].tap()
    XCTAssertTrue(app.staticTexts["bodyMap.selection"].label.contains("臀"))
    attach("back-selected", app: app)
    app.buttons["bodyMap.front"].tap()
    XCTAssertEqual(scene.value as? String, "前面")
    app.segmentedControls.buttons["全部未知"].tap()
    XCTAssertTrue(app.staticTexts["待建立记录"].firstMatch.exists)
    attach("unknown", app: app)
    app.segmentedControls.buttons["全部零分"].tap()
    XCTAssertFalse(app.staticTexts["待建立记录"].firstMatch.exists)
    attach("zero", app: app)
  }

  @MainActor
  func testListExposesAllMusclesAndSelectionCallbacks() {
    let app = XCUIApplication()
    app.launchArguments = ["-fixture-list", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    XCTAssertTrue(app.staticTexts["bodyMap.fallback"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.otherElements["bodyMap.scene"].exists)
    for muscle in ["chest", "back", "shoulders", "biceps", "triceps", "forearms", "core", "glutes", "quads", "hamstrings", "calves"] {
      let row = app.buttons["bodyMap.row.\(muscle)"]
      if !row.isHittable { app.swipeUp() }
      XCTAssertTrue(row.exists)
      row.tap()
      XCTAssertTrue(row.isSelected)
    }
    XCTAssertTrue(app.staticTexts["preview.callback"].label.contains("calves · 11"))
    attach("list-fallback", app: app)
  }

  @MainActor
  private func attach(_ name: String, app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
