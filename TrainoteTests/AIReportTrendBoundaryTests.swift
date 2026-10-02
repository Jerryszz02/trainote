import SwiftData
import XCTest

@testable import Trainote

private struct CapturedTrendDayBuckets: Decodable {
  struct Example: Decodable {
    var name: String
    var timeZone: String
    var asOf: Date
    var day: AnalysisWindow
    var sampleIDs: [UUID]
    var trend: TrendResult
    var input: ReportInput {
      .init(reportType: .trend, asOf: asOf, inputFingerprint: trend.inputFingerprint,
        facts: trend.facts, candidates: [], knowledgeVersion: AIReportPolicy.knowledgeVersion,
        calculationVersions: [trend.calculationVersion], missingData: [])
    }
  }
  var sourceCommit: String
  var examples: [Example]
}

@MainActor
final class AIReportTrendBoundaryTests: XCTestCase {
  private func capture() throws -> CapturedTrendDayBuckets {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ai-report-trend-day-buckets", withExtension: "json"))
    return try AIReportPolicy.decoder().decode(CapturedTrendDayBuckets.self, from: Data(contentsOf: url))
  }
  func testRealBWindowsPreserveAllFactsAndProjectElapsedIntervalsAcrossTimeZones() throws {
    let fixture = try capture()
    XCTAssertEqual(fixture.sourceCommit, "a7e418c6749e6930255370cc9beb4ba737e92594")
    XCTAssertEqual(fixture.examples.count, 10)
    var projectedMetrics: Set<String> = []
    for example in fixture.examples {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = try XCTUnwrap(TimeZone(identifier: example.timeZone))
      let day = try XCTUnwrap(calendar.dateInterval(of: .day, for: example.asOf))
      XCTAssertEqual(example.day.start, day.start); XCTAssertEqual(example.day.end, day.end)
      let input = example.input
      let rejected = input.facts.filter { (try? ReportFactSelection.wireWindow($0, asOf: input.asOf)) == nil }
      XCTAssertEqual(rejected.map(\.metric), [], "Real B scenario: \(example.name)")
      guard rejected.isEmpty else { continue }
      let wire = try ReportWireInput(input)
      XCTAssertEqual(wire.facts.count, input.facts.count, "No fact is dropped to bypass a window error")
      for (local, sent) in zip(input.facts.sorted { $0.id < $1.id }, wire.facts) {
        XCTAssertEqual(sent.metric, local.metric); XCTAssertEqual(sent.value, local.value)
        XCTAssertEqual(sent.unit, local.unit); XCTAssertEqual(sent.quality, local.quality)
        XCTAssertEqual(sent.window.start, local.window.start)
        XCTAssertEqual(sent.window.end, min(local.window.end, input.asOf))
        if local.window.end > input.asOf { projectedMetrics.insert(local.metric) }
      }
      let encoded = String(decoding: try AIReportPolicy.encoder().encode(wire), as: UTF8.self)
      for value in ["org.example", "trend.weight", "dependencies", "sources"] { XCTAssertFalse(encoded.contains(value)) }
      for id in example.sampleIDs { XCTAssertFalse(encoded.contains(id.uuidString)) }
      // Actual B output already excluded the deliberately supplied future weight sample.
      XCTAssertFalse(input.facts.flatMap(\.dependencies).contains { $0.id == AnalysisFixtures.id(4999).uuidString })
      var remote = LocalReportGenerator().make(wire.validationInput)
      remote.reportID = UUID().uuidString; remote.model = AIReportPolicy.model; remote.isLocalFallback = false
      let restored = try ReportResultValidator.decode(AIReportPolicy.encoder().encode(remote), input: input, now: input.asOf)
      XCTAssertTrue(restored.observations.flatMap(\.evidenceIDs).allSatisfy(Set(input.facts.map(\.id)).contains))
      XCTAssertEqual(input.facts, example.trend.facts)
    }
    XCTAssertEqual(projectedMetrics, ["weight.representative", "weight.smoothed", "energy.initialEstimate", "weight.targetWeeklyChangePercent"])
  }
  func testRealBDSTDayLengthsAndMultidaySmoothingAreNotReinterpretedAs24Hours() throws {
    let examples = try capture().examples
    let durations: [String: Double] = ["new-york-spring": 23, "new-york-fall-first-hour": 25,
      "new-york-fall-second-hour": 25, "lord-howe-half-hour": 23.5]
    for (name, hours) in durations {
      let example = try XCTUnwrap(examples.first { $0.name == name })
      XCTAssertEqual(example.day.end.timeIntervalSince(example.day.start), hours * 3600)
      XCTAssertNoThrow(try ReportWireInput(example.input))
    }
    let history = try XCTUnwrap(examples.first { $0.name == "health-history" })
    let smoothed = try XCTUnwrap(history.trend.facts.first { $0.metric == "weight.smoothed" })
    XCTAssertGreaterThan(smoothed.window.end.timeIntervalSince(smoothed.window.start), 27 * 86400)
    XCTAssertEqual(try ReportFactSelection.wireWindow(smoothed, asOf: history.asOf).end, history.asOf)
    let close = try XCTUnwrap(examples.first { $0.name == "near-midnight" })
    XCTAssertEqual(close.day.end.timeIntervalSince(close.asOf), 30)
    XCTAssertTrue(try ReportWireInput(close.input).facts.allSatisfy { $0.window.end <= close.asOf })
  }
  func testRealBEmptyAndHealthDerivedInputsSurviveBasicReportWithoutAIConsent() async throws {
    for example in try capture().examples.filter({ ["empty-midnight", "health-history"].contains($0.name) }) {
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: folder) }
      let consent = try LocalConsentStore(url: folder.appendingPathComponent("consent.json"))
      if example.name == "health-history" {
        try consent.grant(.healthData, version: LocalConsentStore.healthConsentVersion, at: example.asOf)
      }
      let health = FixtureHealthDataProvider(scenario: .manualOnly)
      let builder = ReportSnapshotBuilder(
        repository: SwiftDataAnalysisRepository(container: try PersistenceController.makeContainer(inMemory: true)),
        health: health, consent: consent, trend: FixtureTrendCalculator(),
        recovery: FixtureRecoveryCalculator(), recommendations: FixtureRecommendationProvider())
      let service = AIReportService(builder: builder, consent: consent, healthData: nil,
        cache: try AIReportCache(url: folder.appendingPathComponent("reports.json"), allowHealthHistory: true))
      let result = await service.report(type: .trend, window: example.day, asOf: example.asOf,
        timeZone: try XCTUnwrap(TimeZone(identifier: example.timeZone)), localInput: example.input)
      XCTAssertTrue(result.report.isLocalFallback); XCTAssertEqual(result.input, example.input)
      XCTAssertFalse(result.input.facts.isEmpty); XCTAssertEqual(health.freshRequests, 0)
      XCTAssertFalse(service.isRemoteAvailable); XCTAssertNil(consent.record(for: .aiReports))
      if example.name == "empty-midnight" {
        XCTAssertNil(result.input.facts.first { $0.metric == "weight.smoothed" }?.value)
      }
    }
  }
  func testFutureRawHealthFactsAndUnknownOrMalformedCalculatedBucketsStillFail() throws {
    let example = try XCTUnwrap(capture().examples.first { $0.name == "health-history" })
    let asOf = example.asOf
    let representative = try XCTUnwrap(example.trend.facts.first {
      $0.metric == "weight.representative" && $0.window.end > asOf
    })
    let raw = MetricFact(id: "health.bodyMass.raw", metric: "bodyMass", value: 70, unit: .kilograms,
      window: .init(start: asOf.addingTimeInterval(-30), end: asOf.addingTimeInterval(1)),
      sources: [.init(kind: .healthKit, identifier: "org.example.future-scale")],
      dependencies: [.init(kind: .healthSample, id: AnalysisFixtures.id(4999).uuidString)])
    let mutations: [(inout MetricFact) -> Void] = [
      { $0.id = "health.bodyMass.raw" },
      { $0.id = "trend.weight.representative.not-a-digest" },
      { $0.metric = "weight.futurePrediction" },
      { $0.unit = .milliseconds },
      { $0.window.start = asOf.addingTimeInterval(1) },
      { $0.window.start = asOf.addingTimeInterval(-3 * 86400) },
      { $0.window.end = asOf.addingTimeInterval(48 * 3600) },
    ]
    var invalidFacts = [raw]
    for mutation in mutations { var fact = representative; mutation(&fact); invalidFacts.append(fact) }
    for fact in invalidFacts {
      XCTAssertThrowsError(try ReportFactSelection.wireWindow(fact, asOf: asOf), fact.id)
    }
    var input = example.input
    input.facts.append(raw) // Raw observations are normally omitted from upload, but still must be validated.
    XCTAssertFalse(ReportFactSelection.facts(input).contains { $0.id == raw.id })
    XCTAssertThrowsError(try ReportWireInput(input))
    XCTAssertThrowsError(try ReportWireInput.validateLocal(input))
  }
}
