import XCTest

@testable import Trainote

@MainActor
private final class TestReportLifecycle: AIReportLifecycle {
  var isConfigured = true
  var consentVersion = "test-ai-v1"
  var configurationMessage = "尚未配置"
  var serverRevocationPending = false
  var activationFails = false
  var revokeFails = false
  var deletionFails = false
  var activations = 0
  var cancellations = 0
  var revocations = 0
  var deletions = 0
  var healthDeletions = 0
  func activateConsent() async throws {
    activations += 1
    if activationFails { throw AnalysisFailure.unavailable }
  }
  func cancelPendingRequests() { cancellations += 1 }
  func revokeServerConsent() async throws {
    revocations += 1
    if revokeFails { throw AnalysisFailure.unavailable }
  }
  func deleteAllReports() throws {
    if deletionFails { throw AnalysisFailure.storageFailed }
    deletions += 1
  }
  func deleteHealthDependentData() throws { healthDeletions += 1 }
}

@MainActor
final class HealthFeatureAccessTests: XCTestCase {
  private var directory: URL!
  override func setUp() {
    super.setUp()
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }
  override func tearDown() {
    try? FileManager.default.removeItem(at: directory)
    super.tearDown()
  }
  func testAssemblyDoesNotGrantConsentAndRegistersCacheBeforeUse() throws {
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    let reports = TestReportLifecycle()
    var registered = false
    let access = HealthFeatureAccess(consent: consent, health: nil, reports: reports) { _ in
      registered = true
    }
    XCTAssertTrue(registered)
    XCTAssertFalse(access.aiEnabled)
    XCTAssertFalse(access.healthConnected)
    XCTAssertNil(consent.record(for: .aiReports))
    XCTAssertNil(consent.record(for: .healthData))
    XCTAssertEqual(reports.activations, 0)
  }
  func testUnconfiguredAIHasNoConsentOrActivation() async throws {
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    let reports = TestReportLifecycle()
    reports.isConfigured = false
    let access = HealthFeatureAccess(consent: consent, health: nil, reports: reports) { _ in }
    await access.enableAI()
    XCTAssertEqual(reports.activations, 0)
    XCTAssertNil(consent.record(for: .aiReports))
    XCTAssertNotNil(access.errorMessage)
  }
  func testAIRevocationCancelsEvenIfLocalWriteFailsAndStillCallsServer() async throws {
    var failWrite = false
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json")) {
      data, url in
      if failWrite { throw AnalysisFailure.storageFailed }
      try LocalHealthStorage.write(data, to: url)
    }
    let reports = TestReportLifecycle()
    let access = HealthFeatureAccess(consent: consent, health: nil, reports: reports) { _ in }
    await access.enableAI()
    XCTAssertTrue(access.aiEnabled)
    failWrite = true
    await access.revokeAI()
    XCTAssertFalse(access.aiEnabled)
    XCTAssertGreaterThan(reports.cancellations, 0)
    XCTAssertEqual(reports.revocations, 1)
    XCTAssertTrue(access.aiRevocationNeedsRetry)
    failWrite = false
    await access.revokeAI()
    XCTAssertFalse(access.aiRevocationNeedsRetry)
    XCTAssertNil(access.errorMessage)
  }
  func testActivationFailureRevokesLocalAndServerAndRequiresFreshExplicitConsent() async throws {
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    let reports = TestReportLifecycle()
    reports.activationFails = true
    let access = HealthFeatureAccess(consent: consent, health: nil, reports: reports) { _ in }
    await access.enableAI()
    XCTAssertFalse(access.aiEnabled)
    XCTAssertEqual(reports.revocations, 1)
    XCTAssertFalse(consent.record(for: .aiReports)!.isGranted)
    reports.activationFails = false
    await access.enableAI()
    XCTAssertTrue(access.aiEnabled)
    XCTAssertEqual(reports.activations, 2)
  }
  func testHealthDisconnectDeletesCacheAndDependentReportsButKeepsAIChoice() async throws {
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    let cache = try HealthCacheStore(
      url: directory.appendingPathComponent("cache.json"), syncStart: AnalysisFixtures.window.start)
    let health = HealthDataService(client: FakeHealthQueryClient(), cache: cache, consent: consent)
    let reports = TestReportLifecycle()
    let access = HealthFeatureAccess(consent: consent, health: health, reports: reports) {
      health.addDerivedDataInvalidator($0)
    }
    try consent.grant(.healthData, version: LocalConsentStore.healthConsentVersion, at: .now)
    await access.enableAI()
    await access.disconnectHealth()
    XCTAssertFalse(access.healthConnected)
    XCTAssertTrue(access.aiEnabled)
    XCTAssertEqual(reports.healthDeletions, 1)
    XCTAssertFalse(access.healthDeletionNeedsRetry)
    XCTAssertTrue(try health.localSnapshot(window: AnalysisFixtures.window).samples.isEmpty)
  }
  func testDisconnectFailureIsNotReportedAsSuccessfulDeletion() async throws {
    let reports = TestReportLifecycle()
    let access = HealthFeatureAccess(consent: nil, health: nil, reports: reports) { _ in }
    await access.disconnectHealth()
    XCTAssertTrue(access.healthDeletionNeedsRetry)
    XCTAssertNil(access.statusMessage)
    XCTAssertNotNil(access.errorMessage)
  }
  func testServerFailureRemainsRetryableAndDeletingReportsDoesNotRevokeHealth() async throws {
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    try consent.grant(.healthData, version: LocalConsentStore.healthConsentVersion, at: .now)
    let reports = TestReportLifecycle()
    let access = HealthFeatureAccess(consent: consent, health: nil, reports: reports) { _ in }
    await access.enableAI()
    reports.revokeFails = true
    await access.revokeAI()
    XCTAssertTrue(access.aiRevocationNeedsRetry)
    XCTAssertTrue(access.healthConnected)
    access.deleteReports()
    XCTAssertEqual(reports.deletions, 1)
    XCTAssertTrue(access.healthConnected)
    let reopened = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    XCTAssertFalse(reopened.record(for: .aiReports)!.isGranted)
    XCTAssertTrue(reopened.record(for: .healthData)!.isGranted)
  }
}
