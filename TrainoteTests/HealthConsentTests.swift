import SwiftData
import XCTest

@testable import Trainote

private struct HealthDependentTrend: TrendCalculating {
  var staleFact: MetricFact? = nil
  func calculate(_ input: AnalysisInput) throws -> TrendResult {
    let base =
      staleFact
      ?? input.health.facts.first { $0.metric == HealthDataType.heartRateVariabilitySDNN.rawValue }
    let facts =
      base.map { fact in
        [
          MetricFact(
            id: "derived.hrv", metric: "baseline.hrv", value: fact.value, unit: fact.unit,
            window: fact.window, sources: [.init(kind: .calculation, identifier: "test")],
            dependencies: [.init(kind: .metricFact, id: fact.id)])
        ]
      } ?? []
    return .init(
      inputFingerprint: input.inputFingerprint, points: [], weeklyChangeKilograms: nil,
      weeklyChangePercent: nil, proposal: nil, holdReason: .baselineBuilding, facts: facts,
      calculationVersion: "test")
  }
}

@MainActor
final class HealthConsentTests: XCTestCase {
  private var directory: URL!
  override func setUp() {
    super.setUp()
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }
  override func tearDown() {
    try? FileManager.default.removeItem(at: directory)
    super.tearDown()
  }
  func testScopesAreIndependentRevocationInvalidatesLeaseAndReenableNeedsNewLease() throws {
    let url = directory.appendingPathComponent("consent.json")
    let consent = try LocalConsentStore(url: url)
    XCTAssertThrowsError(
      try consent.lease(for: .aiReports, version: LocalConsentStore.aiConsentVersion))
    try consent.grant(
      .healthData, version: LocalConsentStore.healthConsentVersion, at: AnalysisFixtures.asOf)
    XCTAssertNil(consent.record(for: .aiReports))
    try consent.grant(
      .aiReports, version: LocalConsentStore.aiConsentVersion, at: AnalysisFixtures.asOf)
    let lease = try consent.lease(for: .aiReports, version: LocalConsentStore.aiConsentVersion)
    var cancelled = false
    consent.onRevocation(.aiReports) { cancelled = true }
    try consent.revoke(.aiReports, at: AnalysisFixtures.asOf)
    XCTAssertTrue(cancelled)
    XCTAssertThrowsError(try consent.validate(lease))
    XCTAssertTrue(consent.record(for: .healthData)!.isGranted)
    let reopened = try LocalConsentStore(url: url)
    XCTAssertFalse(reopened.record(for: .aiReports)!.isGranted)
    try consent.grant(.aiReports, version: "ai-report-v2", at: AnalysisFixtures.asOf)
    XCTAssertThrowsError(
      try consent.lease(for: .aiReports, version: LocalConsentStore.aiConsentVersion))
    XCTAssertThrowsError(try consent.validate(lease))
    XCTAssertTrue(
      try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
  }
  func testNoAIConsentStopsBeforeReadingOrGenerating() async throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let health = FixtureHealthDataProvider(scenario: .aiDeclined)
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    let builder = ReportSnapshotBuilder(
      repository: SwiftDataAnalysisRepository(container: container),
      health: health, consent: consent, trend: FixtureTrendCalculator(),
      recovery: FixtureRecoveryCalculator(),
      recommendations: FixtureRecommendationProvider())
    do {
      _ = try await builder.prepare(
        type: .today, window: AnalysisFixtures.window, asOf: AnalysisFixtures.asOf,
        timeZone: TimeZone(secondsFromGMT: 0)!, knowledgeVersion: "fixture",
        consentVersion: LocalConsentStore.aiConsentVersion)
      XCTFail("Expected consentRequired")
    } catch { XCTAssertEqual(error as? AnalysisFailure, .consentRequired) }
    XCTAssertEqual(health.freshRequests, 0)
  }
  func testFreshReportRebuildRemovesIndirectOldHealthFacts() async throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    try consent.grant(
      .healthData, version: LocalConsentStore.healthConsentVersion, at: AnalysisFixtures.asOf)
    try consent.grant(
      .aiReports, version: LocalConsentStore.aiConsentVersion, at: AnalysisFixtures.asOf)
    let client = FakeHealthQueryClient()
    let cache = try HealthCacheStore(
      url: directory.appendingPathComponent("cache.json"), syncStart: AnalysisFixtures.window.start)
    let sample = AnalysisFixtures.health(.complete).samples.first {
      $0.type == .heartRateVariabilitySDNN
    }!
    try cache.commit(
      .init(
        type: .heartRateVariabilitySDNN, added: [sample], deletedIDs: [],
        newAnchor: Data([1]), queriedAt: AnalysisFixtures.asOf))
    client.samplesByType[.heartRateVariabilitySDNN] = [sample]
    let health = HealthDataService(
      client: client, cache: cache, consent: consent, clock: { AnalysisFixtures.asOf })
    let builder = ReportSnapshotBuilder(
      repository: SwiftDataAnalysisRepository(container: container),
      health: health, consent: consent, trend: HealthDependentTrend(),
      recovery: FixtureRecoveryCalculator(),
      recommendations: FixtureRecommendationProvider())
    let before = try await builder.prepare(
      type: .trend, window: AnalysisFixtures.window, asOf: AnalysisFixtures.asOf,
      timeZone: TimeZone(secondsFromGMT: 0)!, knowledgeVersion: "fixture",
      consentVersion: LocalConsentStore.aiConsentVersion)
    XCTAssertTrue(before.input.facts.contains { $0.id == "derived.hrv" })
    XCTAssertTrue(
      before.input.facts.first { $0.id == "derived.hrv" }!.dependencies.contains {
        $0.kind == .healthSample && $0.id == sample.id.uuidString
      })
    client.samplesByType = [:]  // System read revocation looks the same as no samples.
    let after = try await builder.prepare(
      type: .trend, window: AnalysisFixtures.window, asOf: AnalysisFixtures.asOf,
      timeZone: TimeZone(secondsFromGMT: 0)!, knowledgeVersion: "fixture",
      consentVersion: LocalConsentStore.aiConsentVersion)
    XCTAssertTrue(after.input.facts.isEmpty)
    XCTAssertEqual(cache.state.samples.count, 1)  // Old cache still exists, but is never used for this report.
    XCTAssertNotEqual(after.input.inputFingerprint, before.input.inputFingerprint)
    try consent.revoke(.aiReports, at: AnalysisFixtures.asOf)
    XCTAssertThrowsError(try builder.validateBeforeSending(after))
  }
  func testDisconnectClearsDependentReportsAndPreservesManualRecords() async throws {
    final class Reports: HealthDerivedDataInvalidating {
      var hasHealthReport = true
      func deleteHealthDependentData() throws { hasHealthReport = false }
    }
    let container = try PersistenceController.makeContainer(inMemory: true)
    let repo = SwiftDataAnalysisRepository(container: container)
    let date = AnalysisFixtures.asOf
    try repo.saveWeight(
      .init(
        id: UUID(), measuredAt: date, kilograms: 70,
        timeZoneIdentifier: "UTC", createdAt: date, updatedAt: date))
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    try consent.grant(.healthData, version: LocalConsentStore.healthConsentVersion, at: date)
    try consent.grant(.aiReports, version: LocalConsentStore.aiConsentVersion, at: date)
    let cache = try HealthCacheStore(
      url: directory.appendingPathComponent("cache.json"), syncStart: AnalysisFixtures.window.start)
    let service = HealthDataService(client: FakeHealthQueryClient(), cache: cache, consent: consent)
    let reports = Reports()
    service.addDerivedDataInvalidator(reports)
    try await service.disconnectAndDelete()
    XCTAssertFalse(reports.hasHealthReport)
    XCTAssertEqual(try repo.manualRecords().weights.count, 1)
    XCTAssertTrue(consent.record(for: .aiReports)!.isGranted)
  }

  func testRevocationDuringFreshReadFailsClosed() async throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    try consent.grant(
      .healthData, version: LocalConsentStore.healthConsentVersion, at: AnalysisFixtures.asOf)
    try consent.grant(
      .aiReports, version: LocalConsentStore.aiConsentVersion, at: AnalysisFixtures.asOf)
    let client = FakeHealthQueryClient()
    client.onSamples = {
      try consent.revoke(.aiReports, at: AnalysisFixtures.asOf)
      client.onSamples = nil
    }
    let cache = try HealthCacheStore(
      url: directory.appendingPathComponent("cache.json"), syncStart: AnalysisFixtures.window.start)
    let builder = ReportSnapshotBuilder(
      repository: SwiftDataAnalysisRepository(container: container),
      health: HealthDataService(client: client, cache: cache, consent: consent), consent: consent,
      trend: FixtureTrendCalculator(), recovery: FixtureRecoveryCalculator(),
      recommendations: FixtureRecommendationProvider())
    do {
      _ = try await builder.prepare(
        type: .today, window: AnalysisFixtures.window, asOf: AnalysisFixtures.asOf,
        timeZone: TimeZone(secondsFromGMT: 0)!, knowledgeVersion: "fixture",
        consentVersion: LocalConsentStore.aiConsentVersion)
      XCTFail("Expected consentChanged")
    } catch { XCTAssertEqual(error as? AnalysisFailure, .consentChanged) }
  }
}
