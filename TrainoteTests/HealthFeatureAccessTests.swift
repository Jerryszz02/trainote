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
  func testOpenStatusAndErrorSwitchLanguageWithoutRepeatingOperations() async throws {
    let preference = LanguageSettings.shared.preference
    defer { LanguageSettings.shared.preference = preference }
    LanguageSettings.shared.preference = .english
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    let reports = TestReportLifecycle()
    let access = HealthFeatureAccess(consent: consent, health: nil, reports: reports) { _ in }
    await access.enableAI()
    XCTAssertEqual(access.statusMessage, "AI reports enabled. You can turn them off in settings at any time.")
    let activationCount = reports.activations
    let storedConsent = consent.record(for: .aiReports)
    LanguageSettings.shared.preference = .simplifiedChinese
    XCTAssertEqual(access.statusMessage, "已启用 AI 报告。可随时在设置中关闭。")
    XCTAssertEqual(reports.activations, activationCount)
    XCTAssertEqual(consent.record(for: .aiReports), storedConsent)
    await access.connectHealth()
    XCTAssertEqual(access.errorMessage, "健康读取暂不可用。原有记录可继续使用，请重新启动后重试。")
    LanguageSettings.shared.preference = .english
    XCTAssertEqual(access.errorMessage, "Health reads are unavailable. Existing records are still available. Restart and try again.")
    XCTAssertEqual(reports.activations, activationCount)
    reports.deletionFails = true
    access.deleteReports()
    XCTAssertEqual(access.errorMessage, "Report deletion is incomplete. Try again.")
    LanguageSettings.shared.preference = .simplifiedChinese
    XCTAssertEqual(access.errorMessage, "报告删除未完成，请重试。")
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
  func testHealthStatusSeparatesRequestEmptySamplesImportedDataAndSyncFailure() async throws {
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    let cache = try HealthCacheStore(
      url: directory.appendingPathComponent("cache.json"), syncStart: AnalysisFixtures.window.start)
    let client = FakeHealthQueryClient()
    let health = HealthDataService(client: client, cache: cache, consent: consent)
    let access = HealthFeatureAccess(
      consent: consent, health: health, reports: TestReportLifecycle()) { _ in }
    XCTAssertEqual(access.healthConnectionLabel, L10n.text("health.healthfeatureaccess.not.connected.f2f3e9"))

    await access.connectHealth()
    XCTAssertTrue(access.healthConnected, "本地同意只说明已请求健康读取")
    XCTAssertEqual(access.healthConnectionLabel, L10n.text("health.healthfeatureaccess.no.health.samples.read.yet.e36db5"))
    XCTAssertTrue(access.healthConnectionDetail?.contains(L10n.text("health.healthfeatureaccess.the.latest.sync.completed.d74893")) == true)
    XCTAssertTrue(access.healthConnectionDetail?.contains(L10n.text("health.healthfeatureaccess.no.imported.samples.are.on.this.6c714c")) == true)

    let sample = AnalysisFixtures.health(.complete).samples[0]
    client.batches[.bodyMass] = .init(
      type: .bodyMass, added: [sample], deletedIDs: [],
      newAnchor: Data([1]), queriedAt: AnalysisFixtures.asOf)
    try await health.refresh()
    XCTAssertEqual(access.healthConnectionLabel, L10n.text("health.healthfeatureaccess.imported.health.data.on.this.device.1ce009"))
    XCTAssertTrue(access.healthConnectionDetail?.contains(L10n.text("health.healthfeatureaccess.imported.samples.are.on.this.device.8f3704")) == true)

    client.failedTypes = [.sleep]
    do {
      try await health.refresh()
      XCTFail("Expected the sleep query to fail")
    } catch {}
    XCTAssertEqual(access.healthConnectionLabel, L10n.text("health.healthfeatureaccess.some.health.data.did.not.sync.6df122"))
    XCTAssertTrue(access.healthConnectionDetail?.contains(L10n.text("health.healthfeatureaccess.the.latest.sync.partly.failed.40658f")) == true)
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

  func testForegroundRetryClearsFailureOnlyAfterClosingBothSidesAgain() async throws {
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    let reports = TestReportLifecycle()
    let access = HealthFeatureAccess(consent: consent, health: nil, reports: reports) { _ in }
    await access.enableAI()
    reports.revokeFails = true
    await access.revokeAI()
    XCTAssertTrue(access.aiRevocationNeedsRetry)
    reports.revokeFails = false
    await access.resumePendingRevocation()
    XCTAssertEqual(reports.revocations, 2)
    XCTAssertFalse(access.aiRevocationNeedsRetry)
    XCTAssertNil(access.errorMessage)
    let reopened = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    XCTAssertFalse(reopened.record(for: .aiReports)!.isGranted)
  }
}
