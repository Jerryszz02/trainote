import XCTest

final class RecoveryRIRUITests: XCTestCase {
  func testRIRAndRoleSurviveHistoricalEditAndNewTrainingResetsRIR() {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
    app.launch()
    app.tabBars.buttons["训练"].tap()
    app.buttons["training.start"].tap()
    app.buttons["training.startBlank"].tap()
    app.buttons["workout.addExercise"].tap()
    let search = app.searchFields.firstMatch
    search.tap()
    search.typeText("barbell bench press")
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
