import XCTest

final class HealthAdviceReportsUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
    app.launch()
  }

  func testLocalReportUsesRealFactsAndHistoryRemainsReadOnly() {
    app.tabBars.buttons["趋势"].tap()
    app.buttons["trend.continueCurrentMode"].tap()
    app.buttons["trend.addWeight"].tap()
    UITestTextInput.replace(app.textFields["trend.weight.kilograms"], with: "70", in: app)
    app.buttons["trend.weight.save"].tap()
    app.tabBars.buttons["今日"].tap()
    let reports = app.buttons["today.analysisReports"]
    reveal(reports)
    reports.tap()
    let card = app.descendants(matching: .any)["reports.current"].firstMatch
    XCTAssertTrue(card.waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["基础报告"].exists)
    XCTAssertFalse(app.buttons["health.aiConsent"].exists)
    capture("真实本地基础报告")
    let details = app.buttons["查看依据与说明"]
    reveal(details)
    details.tap()
    XCTAssertTrue(app.navigationBars["报告依据"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["事实与依据"].exists)
    let weightFact = app.descendants(matching: .any)["reports.fact.weight.representative"]
      .firstMatch
    reveal(weightFact)
    XCTAssertTrue(weightFact.isHittable, "报告应包含刚保存的真实手动体重")
    XCTAssertTrue(weightFact.label.contains("70kg"))
    XCTAssertTrue(weightFact.label.contains("手动记录"))
    capture("报告依据中的真实手动体重")
    app.navigationBars.buttons.element(boundBy: 0).tap()
    let disclosure = app.staticTexts["reports.localOnly"]
    reveal(disclosure)
    XCTAssertTrue(disclosure.isHittable)
    let history = app.buttons["reports.history"]
    reveal(history)
    history.tap()
    XCTAssertTrue(app.staticTexts["暂无历史 AI 报告"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["确认并开始"].exists)
  }

  func testExplicitAdviceAdoptionStartsANewReducedWorkout() {
    app.buttons["today.library"].tap()
    app.buttons["训练模板"].tap()
    app.buttons["routine.create"].tap()
    app.buttons["routine.addExercise"].tap()
    UITestTextInput.replace(app.searchFields.firstMatch, with: "barbell bench press", in: app)
    app.buttons["exercisePicker.item.0025"].tap()
    app.buttons["routine.save"].tap()

    app.tabBars.buttons["训练"].tap()
    app.buttons["training.start"].tap()
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'training.startRoutine.'"))
      .firstMatch.tap()
    let completed = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH 'strengthSet.complete.'"))
    completed.firstMatch.tap()
    app.buttons["workout.finish"].tap()

    app.tabBars.buttons["恢复"].tap()
    app.buttons["recovery.trainingAdvice"].tap()
    XCTAssertTrue(app.buttons["advice.selectedRoutine"].waitForExistence(timeout: 3))
    app.buttons["advice.selectedRoutine"].tap()
    app.buttons["新训练模板"].tap()
    app.buttons["advice.refresh"].tap()
    let reduce = app.buttons["advice.start.reduceSets"]
    reveal(reduce)
    XCTAssertTrue(reduce.isHittable)
    reduce.tap()
    let parameters = app.buttons["advice.parameters.confirm"]
    reveal(parameters)
    parameters.tap()
    app.buttons["确认并开始"].tap()
    XCTAssertTrue(app.navigationBars["进行中"].waitForExistence(timeout: 5))
    XCTAssertEqual(completed.count, 1)
    let rir = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'strengthSet.rir.'"))
      .firstMatch
    XCTAssertTrue(rir.label.contains("未记录"))
    XCTAssertTrue(app.tabBars.buttons["训练"].isSelected)
    capture("按建议新建减量训练")
  }

  private func reveal(_ element: XCUIElement) {
    for _ in 0..<8 {
      if element.exists && element.isHittable { return }
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
