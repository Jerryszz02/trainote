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
    // This point is on the right pectoral volume, inside the rendered body rather than a tag.
    scene.coordinate(withNormalizedOffset: CGVector(dx: 0.565, dy: 0.292)).tap()
    XCTAssertTrue(app.staticTexts["bodyMap.selection"].label.contains("胸"))
    app.buttons["bodyMap.label.chest"].tap()
    XCTAssertTrue(app.staticTexts["bodyMap.selection"].label.contains("胸"))
    scene.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.6))
      .press(
        forDuration: 0.05,
        thenDragTo: scene.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6)))
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
  func testAccessibilityAuditForList() throws {
    let app = XCUIApplication()
    app.launchArguments = [
      "-fixture-list", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
    ]
    app.launch()
    XCTAssertTrue(app.buttons["bodyMap.row.chest"].waitForExistence(timeout: 10))
    try app.performAccessibilityAudit(for: [
      .contrast, .hitRegion, .sufficientElementDescription, .trait,
    ])
  }

  @MainActor
  func testAccessibilityAuditForScene() throws {
    let app = XCUIApplication()
    app.launch()
    XCTAssertTrue(app.otherElements["bodyMap.scene"].waitForExistence(timeout: 10))
    try app.performAccessibilityAudit(for: [
      .contrast, .hitRegion, .sufficientElementDescription, .trait,
    ])
  }

  @MainActor
  func testDarkSceneAndLargeTextFallback() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-fixture-dark"]
    app.launch()
    XCTAssertTrue(app.otherElements["bodyMap.scene"].waitForExistence(timeout: 10))
    attach("dark", app: app)
    try app.performAccessibilityAudit(for: [
      .contrast, .hitRegion, .sufficientElementDescription, .trait,
    ])
    app.terminate()
    app.launchArguments = ["-fixture-dark", "-fixture-large-text"]
    app.launch()
    XCTAssertTrue(app.staticTexts["bodyMap.fallback"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.otherElements["bodyMap.scene"].exists)
    XCTAssertTrue(app.buttons["bodyMap.row.chest"].label.contains("85 分"))
    try app.performAccessibilityAudit(for: [
      .contrast, .textClipped, .hitRegion, .sufficientElementDescription,
    ])
    attach("large-text", app: app)
  }

  @MainActor
  func testNormalRotationPerformanceAndIdleRendering() async throws {
    try await performance(economical: false)
  }

  @MainActor
  func testEconomicalRotationPerformanceAndIdleRendering() async throws {
    try await performance(economical: true)
  }

  @MainActor
  private func performance(economical: Bool) async throws {
    let app = XCUIApplication()
    app.launchArguments = ["-fixture-benchmark"] + (economical ? ["-fixture-economical"] : [])
    app.launch()
    let result = app.staticTexts["preview.performance"]
    let completed = expectation(
      for: NSPredicate(format: "label CONTAINS 'idle='"), evaluatedWith: result)
    await fulfillment(of: [completed], timeout: 20)
    let idle = result.label.split(separator: " ").first(where: { $0.hasPrefix("idle=") })
      .flatMap { Int($0.dropFirst(5)) }
    XCTAssertLessThanOrEqual(try XCTUnwrap(idle), 3, result.label)
    let report = XCTAttachment(string: result.label)
    report.name = economical ? "performance-economical" : "performance-standard"
    report.lifetime = .keepAlways
    add(report)
    attach(economical ? "economical" : "performance", app: app)
  }

  @MainActor
  func testListExposesAllMusclesAndSelectionCallbacks() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-fixture-list", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
    ]
    app.launch()
    XCTAssertTrue(app.staticTexts["bodyMap.fallback"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.otherElements["bodyMap.scene"].exists)
    for muscle in [
      "chest", "back", "shoulders", "biceps", "triceps", "forearms", "core", "glutes", "quads",
      "hamstrings", "calves",
    ] {
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
