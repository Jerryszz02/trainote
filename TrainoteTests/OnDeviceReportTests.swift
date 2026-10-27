import SwiftData
import XCTest
@testable import Trainote

private actor SelectionTestRuntime: OnDeviceModelRuntime {
  private(set) var calls = 0
  private let output: String
  private let wait: Bool
  private let onStart: (@Sendable () -> Void)?
  private var continuation: CheckedContinuation<String, Never>?
  init(output: String = "{\"factIDs\":[\"f0\"],\"actionIDs\":[\"a0\"]}",
       wait: Bool = false, onStart: (@Sendable () -> Void)? = nil) {
    self.output = output; self.wait = wait; self.onStart = onStart
  }
  func generate(prompt: String, grammar: String, maximumTokens: Int) async throws -> String {
    calls += 1
    if wait {
      // Intentionally ignores cancellation. The caller must reject the late completion.
      return await withCheckedContinuation { continuation = $0; onStart?() }
    }
    onStart?()
    return output
  }
  func finish() { continuation?.resume(returning: output); continuation = nil }
}

@MainActor
final class OnDeviceReportTests: XCTestCase {
  private var directory: URL!
  private let now = AnalysisFixtures.asOf
  override func setUp() {
    super.setUp()
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }
  override func tearDown() {
    try? FileManager.default.removeItem(at: directory)
    super.tearDown()
  }
  private func input(type: ReportType = .today) -> ReportInput {
    .init(reportType: type, asOf: now, inputFingerprint: String(repeating: "a", count: 64),
      facts: [.init(id: "manual.weight", metric: "weight.smoothed", value: 70, unit: .kilograms,
                   window: .init(start: now.addingTimeInterval(-86400), end: now), sources: [.manual])],
      candidates: [.init(actionID: "plan.choose", action: .choosePlan, muscleIDs: [], reasonFactIDs: [])],
      goalDirection: .maintain, knowledgeVersion: AIReportPolicy.knowledgeVersion,
      calculationVersions: ["trend-v1"], missingData: [])
  }
  private func harness(runtime: SelectionTestRuntime) throws
    -> (AIReportService, AIReportCache, LocalConsentStore) {
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    let repository = SwiftDataAnalysisRepository(container: try PersistenceController.makeContainer(inMemory: true))
    let builder = ReportSnapshotBuilder(repository: repository,
      health: FixtureHealthDataProvider(scenario: .manualOnly), consent: consent,
      trend: TrendCalculator(), recovery: FixtureRecoveryCalculator(), recommendations: FixtureRecommendationProvider())
    let cache = try AIReportCache(url: directory.appendingPathComponent("reports.json"), allowHealthHistory: true)
    let time = now
    return (AIReportService(builder: builder, consent: consent, healthData: nil, cache: cache,
      onDeviceGenerator: OnDeviceReportGenerator(runtime: runtime, clock: { time }), clock: { time }), cache, consent)
  }

  func testSelectionWithoutCloudConsentUsesCanonicalBilingualPresentation() async throws {
    let runtime = SelectionTestRuntime()
    let (service, cache, consent) = try harness(runtime: runtime)
    let input = input()
    let content = await service.generateOnDevice(input, validateCurrent: {})
    XCTAssertFalse(content.report.isLocalFallback)
    XCTAssertEqual(content.report.model, OnDeviceReportPolicy.model)
    XCTAssertEqual(content.report.observations.first?.evidenceIDs, ["manual.weight"])
    XCTAssertEqual(content.report.recommendations.first?.actionID, "plan.choose")
    XCTAssertNil(consent.record(for: .aiReports))
    XCTAssertNil(consent.record(for: .healthData))
    XCTAssertEqual(try cache.currentOnDevice(input, now: now)?.id, content.id)
    let previous = LanguageSettings.shared.preference
    defer { LanguageSettings.shared.preference = previous }
    LanguageSettings.shared.preference = .simplifiedChinese
    let chinese = ReportPresentation.summary(content.report)
    LanguageSettings.shared.preference = .english
    XCTAssertNotEqual(ReportPresentation.summary(content.report), chinese)
    XCTAssertTrue(ReportPresentation.supports(content.report))
    XCTAssertTrue(ReportPresentation.display(try XCTUnwrap(content.report.observations.first), facts: input.facts).contains("70"))
    let count = await runtime.calls
    XCTAssertEqual(count, 1)
  }

  func testStrictSelectionRejectsUnknownIDsExtraKeysDuplicatesOversizeAndProse() throws {
    let request = try OnDeviceReportRequest(input())
    for output in [
      "{\"factIDs\":[\"f999\"],\"actionIDs\":[]}",
      "{\"factIDs\":[],\"actionIDs\":[\"a999\"]}",
      "{\"factIDs\":[],\"actionIDs\":[],\"value\":999}",
      "{\"factIDs\":[\"f0\",\"f0\"],\"actionIDs\":[]}",
      "{\"factIDs\":[],\"actionIDs\":[\"a0\",\"a0\"]}",
      "{\"factIDs\":[\"f0\",\"f1\",\"f2\",\"f3\"],\"actionIDs\":[]}",
      "{\"factIDs\":[],\"actionIDs\":[\"a0\",\"a1\",\"a2\",\"a3\"]}",
      "Here is your report: {\"factIDs\":[],\"actionIDs\":[]}",
      "```json\n{\"factIDs\":[],\"actionIDs\":[]}\n```",
      "{\"factIDs\":[{\"id\":\"f0\",\"value\":100}],\"actionIDs\":[]}"
    ] { XCTAssertThrowsError(try request.result(from: output, now: now), output) }
    XCTAssertNoThrow(try request.result(from: "{\"factIDs\":[],\"actionIDs\":[]}", now: now))
  }

  func testOnDeviceValidatorRejectsTamperedNumbersIdentityAndNarrative() throws {
    let input = input()
    let original = try OnDeviceReportRequest(input).result(from: "{\"factIDs\":[\"f0\"],\"actionIDs\":[\"a0\"]}", now: now)
    var altered = original
    altered.observations[0].text = "Your body weight is 999 kg."
    XCTAssertThrowsError(try ReportResultValidator.validateOnDevice(altered, input: input, now: now))
    altered = original; altered.summary = "You are fully recovered."
    XCTAssertThrowsError(try ReportResultValidator.validateOnDevice(altered, input: input, now: now))
    altered = original; altered.inputFingerprint = String(repeating: "b", count: 64)
    XCTAssertThrowsError(try ReportResultValidator.validateOnDevice(altered, input: input, now: now))
    altered = original; altered.model = AIReportPolicy.model
    XCTAssertThrowsError(try ReportResultValidator.validateOnDevice(altered, input: input, now: now))
    XCTAssertThrowsError(try ReportResultValidator.validate(original, input: input, now: now), "Cloud validation remains strict")
  }

  func testTrendSelectionOnlyAllowsNutritionActions() throws {
    var input = input(type: .trend)
    input.candidates.append(.init(actionID: "nutrition.review", action: .reviewNutrition,
                                 muscleIDs: [], reasonFactIDs: ["manual.weight"]))
    let request = try OnDeviceReportRequest(input)
    XCTAssertEqual(request.candidates.map(\.action), [.reviewNutrition])
    let result = try request.result(from: "{\"factIDs\":[\"f0\"],\"actionIDs\":[\"a0\"]}", now: now)
    XCTAssertEqual(result.recommendations.first?.actionID, "nutrition.review")
    var tampered = result
    tampered.recommendations = [.init(text: ReportText.action(.choosePlan), actionID: "plan.choose")]
    XCTAssertThrowsError(try ReportResultValidator.validateOnDevice(tampered, input: input, now: now))
  }

  func testRuleRemoteAndOnDeviceCachesRemainSeparateAndHistoryKeepsOriginalIdentity() throws {
    let runtime = SelectionTestRuntime()
    let (_, cache, _) = try harness(runtime: runtime)
    let input = input()
    let local = try OnDeviceReportRequest(input).result(from: "{\"factIDs\":[\"f0\"],\"actionIDs\":[\"a0\"]}", now: now)
    var remote = local
    remote.reportID = UUID().uuidString
    remote.model = AIReportPolicy.model
    remote.promptVersion = AIReportPolicy.promptVersion
    try cache.save(.init(report: remote, input: input, dependsOnHealth: false))
    XCTAssertNil(try cache.currentOnDevice(input, now: now))
    try cache.save(.init(report: LocalReportGenerator().make(input), input: input, dependsOnHealth: false))
    XCTAssertEqual(cache.history().count, 1, "Rule results are not AI history")
    try cache.save(.init(report: local, input: input, dependsOnHealth: false))
    XCTAssertEqual(try cache.current(input, now: now)?.report.model, AIReportPolicy.model)
    XCTAssertEqual(try cache.currentOnDevice(input, now: now)?.report.model, OnDeviceReportPolicy.model)
    XCTAssertNotEqual(try AIReportCache.key(input), try AIReportCache.key(input, model: OnDeviceReportPolicy.model, promptVersion: OnDeviceReportPolicy.promptVersion))
    let reopened = try AIReportCache(url: directory.appendingPathComponent("reports.json"), allowHealthHistory: true)
    XCTAssertEqual(Set(reopened.history().map { $0.report.model }), [AIReportPolicy.model, OnDeviceReportPolicy.model])
    XCTAssertEqual(reopened.history().first { $0.id == remote.reportID }?.report, remote)
    try reopened.delete(reportID: local.reportID)
    XCTAssertNil(try reopened.currentOnDevice(input, now: now))
    XCTAssertEqual(reopened.history().map(\.id), [remote.reportID])
  }

  func testAutomaticRefreshAndDisabledPreferenceDoNotCallModelOrExposeAICache() async throws {
    let runtime = SelectionTestRuntime()
    let (service, _, _) = try harness(runtime: runtime)
    let input = input()
    XCTAssertTrue(service.refreshOnDevice(input, allowAI: true).report.isLocalFallback)
    let before = await runtime.calls
    XCTAssertEqual(before, 0)
    let generated = await service.generateOnDevice(input, validateCurrent: {})
    XCTAssertEqual(service.refreshOnDevice(input, allowAI: true).id, generated.id)
    XCTAssertTrue(service.refreshOnDevice(input, allowAI: false).report.isLocalFallback)
    XCTAssertEqual(service.history().map(\.id), [generated.id])
    let after = await runtime.calls
    XCTAssertEqual(after, 1)
  }

  func testLateUncooperativeCompletionCannotPublishAfterCancelRecordChangeOrHealthDisconnect() async throws {
    for reason in ["cancel", "records", "health"] {
      let started = expectation(description: "Runtime started: " + reason)
      let runtime = SelectionTestRuntime(wait: true, onStart: { started.fulfill() })
      let (service, cache, consent) = try harness(runtime: runtime)
      var input = input()
      if reason == "health" {
        try consent.grant(.healthData, version: LocalConsentStore.healthConsentVersion, at: now)
        input.facts[0].sources = [.init(kind: .healthKit, identifier: "fixture.watch")]
      }
      var recordsCurrent = true
      let requestInput = input
      let task = Task {
        await service.generateOnDevice(requestInput) {
          if !recordsCurrent { throw AIReportFailure.stale }
        }
      }
      await fulfillment(of: [started], timeout: 2)
      switch reason {
      case "cancel": service.clearCurrent()
      case "records": recordsCurrent = false
      default: try consent.revoke(.healthData, at: now)
      }
      await runtime.finish()
      let result = await task.value
      XCTAssertTrue(result.report.isLocalFallback, reason)
      XCTAssertTrue(cache.history().isEmpty, reason)
      XCTAssertNotEqual(service.latest?.report.model, OnDeviceReportPolicy.model, reason)
      // Each case uses its own cache file rather than a result left from a previous iteration.
      try cache.deleteAll()
    }
  }

  func testIntegrationRefreshDisableAndProcessingGateNeverLoadModel() async throws {
    let runtime = SelectionTestRuntime(output: "{\"factIDs\":[],\"actionIDs\":[]}")
    let container = try PersistenceController.makeContainer(inMemory: true)
    let foundation = HealthFoundation(container: container, localDirectory: directory)
    let recovery = try RecoveryService()
    let advice = TrainingAdviceController(repository: foundation.repository,
      healthData: foundation.healthData, recovery: recovery, modelContext: container.mainContext)
    let integration = HealthReportIntegration(foundation: foundation, trend: TrendCalculator(),
      recovery: recovery, advice: advice, directory: directory.appendingPathComponent("AIReports"), onDeviceRuntime: runtime)
    await integration.refresh(type: .today)
    XCTAssertTrue(try XCTUnwrap(integration.content).report.isLocalFallback)
    integration.setOnDeviceAIEnabled(false)
    await integration.generateOnDevice(type: .today)
    integration.setOnDeviceAIEnabled(true)
    integration.setProcessingAllowed(false)
    await integration.refresh(type: .today)
    await integration.generateOnDevice(type: .today)
    XCTAssertNil(integration.content)
    XCTAssertNil(foundation.consent?.record(for: .aiReports))
    let count = await runtime.calls
    XCTAssertEqual(count, 0)
  }
  func testIntegrationRejectsLateModelCompletionAfterDisableRecordSaveOrNoticeWithdrawal() async throws {
    for reason in ["disable", "records", "notice"] {
      let started = expectation(description: "Integration runtime started: " + reason)
      let runtime = SelectionTestRuntime(output: "{\"factIDs\":[],\"actionIDs\":[]}",
                                         wait: true, onStart: { started.fulfill() })
      let container = try PersistenceController.makeContainer(inMemory: true)
      let foundation = HealthFoundation(container: container,
        localDirectory: directory.appendingPathComponent(reason))
      let recovery = try RecoveryService()
      let advice = TrainingAdviceController(repository: foundation.repository,
        healthData: foundation.healthData, recovery: recovery, modelContext: container.mainContext)
      let integration = HealthReportIntegration(foundation: foundation, trend: TrendCalculator(),
        recovery: recovery, advice: advice,
        directory: directory.appendingPathComponent(reason + "/AIReports"), onDeviceRuntime: runtime)
      let task = Task { await integration.generateOnDevice(type: .today) }
      await fulfillment(of: [started], timeout: 2)
      switch reason {
      case "disable": integration.setOnDeviceAIEnabled(false)
      case "records":
        let date = Date.now
        try foundation.repository.saveWeight(.init(id: UUID(), measuredAt: date, kilograms: 71,
          timeZoneIdentifier: "UTC", createdAt: date, updatedAt: date))
      default: integration.setProcessingAllowed(false)
      }
      await runtime.finish()
      await task.value
      XCTAssertTrue(integration.history.isEmpty, reason)
      XCTAssertNotEqual(integration.content?.report.model, OnDeviceReportPolicy.model, reason)
      XCTAssertNil(foundation.consent?.record(for: .aiReports))
      let count = await runtime.calls
      XCTAssertEqual(count, 1)
    }
  }

  func testDisablingAIAfterRecordChangeCannotRestoreOldCurrentInput() async throws {
    let runtime = SelectionTestRuntime(output: "{\"factIDs\":[],\"actionIDs\":[]}")
    let container = try PersistenceController.makeContainer(inMemory: true)
    let foundation = HealthFoundation(container: container, localDirectory: directory)
    let recovery = try RecoveryService()
    let advice = TrainingAdviceController(repository: foundation.repository,
      healthData: foundation.healthData, recovery: recovery, modelContext: container.mainContext)
    let integration = HealthReportIntegration(foundation: foundation, trend: TrendCalculator(),
      recovery: recovery, advice: advice, directory: directory.appendingPathComponent("AIReports"), onDeviceRuntime: runtime)
    await integration.refresh(type: .today)
    let oldInput = try XCTUnwrap(integration.content).input
    let date = Date.now
    try foundation.repository.saveWeight(.init(id: UUID(), measuredAt: date, kilograms: 77,
      timeZoneIdentifier: TimeZone.current.identifier, createdAt: date, updatedAt: date))
    XCTAssertNil(integration.content)
    integration.setOnDeviceAIEnabled(false)
    XCTAssertNil(integration.content, "Disabling AI must not resurrect the previous report after a save invalidated it")
    await integration.refresh(type: .today)
    let refreshed = try XCTUnwrap(integration.content)
    XCTAssertNotEqual(refreshed.input.inputFingerprint, oldInput.inputFingerprint)
    XCTAssertTrue(refreshed.report.isLocalFallback)
    let calls = await runtime.calls
    XCTAssertEqual(calls, 0)
  }

}
