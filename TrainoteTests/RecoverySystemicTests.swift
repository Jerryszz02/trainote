import XCTest

@testable import Trainote

final class RecoverySystemicTests: XCTestCase {
  let helper = RecoveryCalculatorTests()
  func facts(count: Int = 24, key: String = "watch|Watch1|SDNN|unspecified") -> [MetricFact] {
    (0..<count).map { index in
      let date = helper.now.addingTimeInterval(-Double(count - 1 - index) * 86_400)
      return .init(
        id:
          "health.heartRateVariabilitySDNN.\(AnalysisFingerprint.localDate(date, timeZone: .gmt))|\(key)",
        metric: "heartRateVariabilitySDNN", value: index < count - 3 ? 50 : 20, unit: .milliseconds,
        window: .init(start: date, end: date),
        sources: [.init(kind: .healthKit, identifier: "watch")],
        dependencies: [
          .init(
            kind: .healthSample, id: "sample-\(key)-\(index)", healthType: .heartRateVariabilitySDNN
          )
        ])
    }
  }
  func testBaselineRequires14DaysAndRetainsAllRawDependencies() throws {
    var input = helper.input([helper.workout()])
    input.health.facts = facts()
    let c = try helper.calculator()
    let result = try c.calculate(input)
    let baseline = try XCTUnwrap(
      result.facts.first { $0.id == "recovery.systemic.heartRateVariabilitySDNN.baseline" })
    XCTAssertEqual(baseline.value, 50)
    XCTAssertEqual(baseline.dependencies.filter { $0.kind == .healthSample }.count, 21)
    input.health.facts = facts(count: 13)
    let missing = try c.calculate(input)
    XCTAssertNil(missing.facts.first { $0.id == baseline.id }?.value)
    XCTAssertEqual(missing.systemicState, .unknown)
    XCTAssertEqual(result.muscles, missing.muscles)
  }
  func testHRVDefinitionsDevicesAndContextsAreNeverPooled() throws {
    var input = helper.input()
    input.health.facts =
      facts(count: 10) + facts(count: 10, key: "watch|Watch2|SDNN|unspecified")
      + facts(count: 10, key: "watch|Watch1|RMSSD|morning")
    let result = try helper.calculator().calculate(input)
    XCTAssertNil(
      result.facts.first { $0.id == "recovery.systemic.heartRateVariabilitySDNN.baseline" }?.value)
  }
  func testSustainedDeviationNeedsCurrentFatigueToLowerSystemicState() throws {
    var input = helper.input([helper.workout()])
    input.health.facts = facts()
    let c = try helper.calculator()
    let baseline = try c.calculate(input)
    XCTAssertEqual(baseline.systemicState, .moderate)
    input.checkIns = [
      .init(
        id: UUID(), localDate: AnalysisFingerprint.localDate(input.asOf, timeZone: .gmt),
        timeZoneIdentifier: "GMT", feeling: .tired, updatedAt: input.asOf)
    ]
    let tired = try c.calculate(input)
    XCTAssertEqual(tired.systemicState, .low)
    XCTAssertEqual(tired.muscles, baseline.muscles)
    input.health.facts.removeAll()
    XCTAssertEqual(try c.calculate(input).systemicState, .moderate)
    input.checkIns.removeAll()
    XCTAssertEqual(try c.calculate(input).systemicState, .unknown)
  }
}
