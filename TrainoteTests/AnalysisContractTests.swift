import XCTest

@testable import Trainote

final class AnalysisContractTests: XCTestCase {
  func testFixturesRoundTripAndUnknownIsNotZero() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for scenario in AnalysisFixtures.Scenario.allCases {
      let value = AnalysisFixtures.input(scenario)
      XCTAssertEqual(try decoder.decode(AnalysisInput.self, from: encoder.encode(value)), value)
      let health = AnalysisFixtures.health(scenario)
      XCTAssertEqual(
        try decoder.decode(HealthDataSnapshot.self, from: encoder.encode(health)), health)
    }
    let unknown = BodyMapPresentation.unknown(asOf: AnalysisFixtures.asOf)
    XCTAssertEqual(unknown.muscles.count, 11)
    XCTAssertEqual(Set(unknown.muscles.map(\.muscleID)).count, 11)
    XCTAssertTrue(unknown.muscles.allSatisfy { $0.score == nil && $0.state == .unknown })
    XCTAssertEqual(
      try decoder.decode(BodyMapPresentation.self, from: encoder.encode(AnalysisFixtures.bodyMap)),
      AnalysisFixtures.bodyMap)
    XCTAssertEqual(
      try decoder.decode(ReportInput.self, from: encoder.encode(AnalysisFixtures.report)),
      AnalysisFixtures.report)
  }

  @MainActor
  func testFakeProvidersNeverNeedSystemAuthorization() async throws {
    let provider = FixtureHealthDataProvider(scenario: .missingHRV)
    let snapshot = try await provider.freshSnapshot(window: AnalysisFixtures.window)
    XCTAssertEqual(
      snapshot.statuses.first { $0.type == .heartRateVariabilitySDNN }?.state, .noSamples)
    XCTAssertEqual(provider.authorizationRequests, 0)
    try await provider.disconnectAndDelete()
    XCTAssertTrue(try provider.localSnapshot(window: AnalysisFixtures.window).samples.isEmpty)
  }
}
