import SwiftData
import XCTest

@testable import Trainote

@MainActor
final class HealthReportIntegrationTests: XCTestCase {
  private var directory: URL!

  override func setUp() {
    super.setUp()
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: directory)
    super.tearDown()
  }

  private func assembly() throws
    -> (
      ModelContainer, HealthFoundation, TrainingAdviceController, HealthReportIntegration,
      HealthFeatureAccess
    )
  {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let foundation = HealthFoundation(container: container, localDirectory: directory)
    let recovery = try RecoveryService()
    let advice = TrainingAdviceController(
      repository: foundation.repository, healthData: foundation.healthData,
      recovery: recovery, modelContext: container.mainContext)
    let reports = HealthReportIntegration(
      foundation: foundation, trend: TrendCalculator(), recovery: recovery, advice: advice,
      directory: directory.appendingPathComponent("AIReports"))
    let access = HealthFeatureAccess(foundation: foundation, reports: reports)
    return (container, foundation, advice, reports, access)
  }

  func testRealCalculatorsProduceLocalReportWithoutAnyConsent() async throws {
    let (_, foundation, _, reports, _) = try assembly()
    XCTAssertNotNil(reports.service)
    XCTAssertFalse(reports.isConfigured)
    await reports.refresh(type: .today, asOf: AnalysisFixtures.asOf, timeZone: .gmt)
    let content = try XCTUnwrap(reports.content, reports.errorMessage ?? "Missing report")
    XCTAssertTrue(content.report.isLocalFallback)
    XCTAssertFalse(content.input.facts.isEmpty)
    XCTAssertTrue(content.input.facts.contains { $0.metric == "weight.smoothed" })
    XCTAssertTrue(
      content.input.facts.contains { $0.metric == "recovery.readiness" && $0.value == nil })
    XCTAssertTrue(content.input.facts.contains { $0.metric == "recommendation.selectedPlan" })
    XCTAssertNotEqual(content.input.inputFingerprint, String(repeating: "0", count: 64))
    XCTAssertNil(foundation.consent?.record(for: .aiReports))
    XCTAssertNil(foundation.consent?.record(for: .healthData))
    XCTAssertTrue(reports.history.isEmpty)
  }

  func testRealTrendDayBucketsAreAcceptedByReportBoundary() throws {
    let (_, foundation, _, _, _) = try assembly()
    let asOf = AnalysisFixtures.asOf
    let window = AnalysisWindow(start: asOf.addingTimeInterval(-90 * 86_400), end: asOf)
    let input = try foundation.repository.analysisInput(
      asOf: asOf, window: window, timeZone: .gmt,
      health: .disconnected(window: window, asOf: asOf))
    let result = try TrendCalculator().calculate(input)
    let rejected = result.facts.filter {
      (try? ReportFactSelection.wireWindow($0, asOf: asOf)) == nil
    }
    XCTAssertEqual(rejected.map(\.metric), [], "Actual B facts must pass E's report boundary")
  }

  func testTemplateAndScheduleChangesInvalidateCurrentReportAtSameClock() async throws {
    let (container, _, advice, reports, _) = try assembly()
    let routine = Routine(name: "本次模板")
    routine.exercises = [
      RoutineExercise(
        sourceExerciseID: "0025", nameEnSnapshot: "Bench", nameZhSnapshot: "卧推",
        orderIndex: 0, trackingMode: .strength, defaultSetCount: 3)
    ]
    container.mainContext.insert(routine)
    try container.mainContext.save()
    advice.selectedRoutineID = routine.id
    await reports.refresh(type: .today, asOf: AnalysisFixtures.asOf, timeZone: .gmt)
    let original = try XCTUnwrap(reports.content).input.inputFingerprint
    routine.name = "已修改模板"
    try container.mainContext.save()
    XCTAssertNil(reports.content)
    await reports.refresh(type: .today, asOf: AnalysisFixtures.asOf, timeZone: .gmt)
    let renamed = try XCTUnwrap(reports.content).input.inputFingerprint
    XCTAssertNotEqual(renamed, original)
    advice.availableWeekdays = []
    XCTAssertNil(reports.content)
    await reports.refresh(type: .today, asOf: AnalysisFixtures.asOf, timeZone: .gmt)
    XCTAssertNotEqual(try XCTUnwrap(reports.content).input.inputFingerprint, renamed)
  }

  func testSavingManualDataInvalidatesTheCurrentCardWithoutDeletingHistory() async throws {
    let (_, foundation, _, reports, _) = try assembly()
    await reports.refresh(type: .today, asOf: AnalysisFixtures.asOf, timeZone: .gmt)
    XCTAssertNotNil(reports.content)
    try foundation.repository.saveWeight(
      .init(
        id: UUID(), measuredAt: AnalysisFixtures.asOf, kilograms: 70,
        timeZoneIdentifier: TimeZone.gmt.identifier, createdAt: AnalysisFixtures.asOf,
        updatedAt: AnalysisFixtures.asOf))
    XCTAssertNil(reports.content)
    XCTAssertTrue(reports.history.isEmpty)
  }

  func testRealLifecycleCloseDisconnectAndDeletePreserveManualRecords() async throws {
    let (_, foundation, _, reports, access) = try assembly()
    try foundation.repository.saveWeight(
      .init(
        id: UUID(), measuredAt: AnalysisFixtures.asOf, kilograms: 70,
        timeZoneIdentifier: TimeZone.gmt.identifier, createdAt: AnalysisFixtures.asOf,
        updatedAt: AnalysisFixtures.asOf))
    let consent = try XCTUnwrap(foundation.consent)
    try consent.grant(.healthData, version: LocalConsentStore.healthConsentVersion, at: .now)
    try consent.grant(.aiReports, version: LocalConsentStore.aiConsentVersion, at: .now)
    await reports.refresh(type: .today, asOf: AnalysisFixtures.asOf, timeZone: .gmt)
    XCTAssertNotNil(reports.content)
    await access.revokeAI()
    XCTAssertFalse(access.aiRevocationNeedsRetry)
    XCTAssertNil(reports.content)
    XCTAssertTrue(access.healthConnected)
    XCTAssertFalse(consent.record(for: .aiReports)?.isGranted == true)
    await access.disconnectHealth()
    XCTAssertFalse(access.healthDeletionNeedsRetry)
    access.deleteReports()
    XCTAssertNil(access.errorMessage)
    XCTAssertNil(reports.content)
    XCTAssertTrue(reports.history.isEmpty)
    XCTAssertEqual(try foundation.repository.manualRecords().weights.count, 1)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("AIReports/reports.json").path))
  }
}
