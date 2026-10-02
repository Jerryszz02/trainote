import SwiftData
import XCTest

@testable import Trainote

private struct CapturedReportContract: Decodable {
  var recoveryCommit: String
  var recommendationCommit: String
  var healthSnapshot: HealthDataSnapshot
  var recoveryResult: RecoveryResult
  var preparedFactCount: Int
  var recommendationInputs: [String: ReportInput]
}
private struct CapturedRecoveryCalculator: RecoveryCalculating {
  var result: RecoveryResult
  func calculate(_ input: AnalysisInput) throws -> RecoveryResult {
    var value = result
    value.inputFingerprint = input.inputFingerprint
    value.asOf = input.asOf
    return value
  }
}
private struct CapturedHealthTrend: TrendCalculating {
  func calculate(_ input: AnalysisInput) throws -> TrendResult {
    var result = AnalysisFixtures.trend
    result.inputFingerprint = input.inputFingerprint
    result.facts = input.health.facts
    return result
  }
}
private final class CapturedRecommendationProvider: RecommendationProviding {
  var value: RecommendationSnapshot
  var analysisFingerprints: [String] = []
  init(_ value: RecommendationSnapshot) { self.value = value }
  func candidates(input: AnalysisInput, trend: TrendResult, recovery: RecoveryResult) throws -> [RecommendationCandidate] {
    throw AnalysisFailure.invalidInput // The builder must take facts and candidates from one snapshot.
  }
  func snapshot(input: AnalysisInput, trend: TrendResult, recovery: RecoveryResult) throws -> RecommendationSnapshot {
    analysisFingerprints.append(input.inputFingerprint)
    return value
  }
}

@MainActor
final class AIReportRealContractTests: XCTestCase {
  private func fixture() throws -> CapturedReportContract {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ai-report-real-contract", withExtension: "json"))
    return try AIReportPolicy.decoder().decode(CapturedReportContract.self, from: Data(contentsOf: url))
  }
  private func remoteResult(_ input: ReportInput) -> ReportResult {
    var result = LocalReportGenerator().make(input)
    result.reportID = UUID().uuidString
    result.model = AIReportPolicy.model
    result.isLocalFallback = false
    return result
  }
  private func freshPreparedInput() async throws -> ReportInput {
    let capture = try fixture()
    XCTAssertEqual(capture.recoveryCommit, "2d2703ef28033d952d0d61a3b950003afe5e97f2")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let consent = try LocalConsentStore(url: folder.appendingPathComponent("consent.json"))
    try consent.grant(.aiReports, version: LocalConsentStore.aiConsentVersion, at: AnalysisFixtures.asOf)
    try consent.grant(.healthData, version: LocalConsentStore.healthConsentVersion, at: AnalysisFixtures.asOf)
    let health = FixtureHealthDataProvider(scenario: .complete)
    health.snapshot = capture.healthSnapshot
    let builder = ReportSnapshotBuilder(
      repository: SwiftDataAnalysisRepository(container: try PersistenceController.makeContainer(inMemory: true)),
      health: health, consent: consent, trend: CapturedHealthTrend(),
      recovery: CapturedRecoveryCalculator(result: capture.recoveryResult), recommendations: FixtureRecommendationProvider())
    let prepared = try await builder.prepare(type: .today, window: capture.healthSnapshot.window,
      asOf: AnalysisFixtures.asOf, timeZone: TimeZone(secondsFromGMT: 0)!,
      knowledgeVersion: AIReportPolicy.knowledgeVersion, consentVersion: LocalConsentStore.aiConsentVersion)
    try builder.validateBeforeSending(prepared)
    XCTAssertEqual(health.freshRequests, 1)
    XCTAssertEqual(capture.healthSnapshot.samples.count, 84)
    XCTAssertEqual(prepared.input.facts.count, capture.preparedFactCount)
    XCTAssertEqual(prepared.input.facts.count, 131)
    // The complete dependency closure still governs freshness and consent even though it is not uploaded.
    XCTAssertTrue(prepared.input.facts.contains { $0.dependencies.contains { $0.kind == .healthSample } })
    try consent.revoke(.healthData, at: AnalysisFixtures.asOf)
    XCTAssertThrowsError(try builder.validateBeforeSending(prepared))
    return prepared.input
  }
  func testActual28DayDependencyClosureProjectsOnlySummariesWithoutLeakingSourceIDs() async throws {
    let input = try await freshPreparedInput()
    let wire = try ReportWireInput(input)
    XCTAssertTrue(wire.calculationVersions.contains("recovery-v0.1+exercise-muscles-v0.1"))
    XCTAssertEqual(wire.facts.count, 47)
    XCTAssertEqual(input.facts.count, 131)
    let bytes = try AIReportPolicy.encoder().encode(wire)
    let encoded = String(decoding: bytes, as: UTF8.self)
    for value in ["org.example.synthetic-health", "Watch14,5", "morning check", "仅本地合成设备", "dependencies", "sources"] {
      XCTAssertFalse(encoded.contains(value), value)
    }
    for sample in try fixture().healthSnapshot.samples { XCTAssertFalse(encoded.contains(sample.id.uuidString)) }
    var reordered = input; reordered.facts.reverse(); reordered.candidates.reverse()
    XCTAssertEqual(bytes, try AIReportPolicy.encoder().encode(ReportWireInput(reordered)))
    // A valid large local closure must remain usable for the basic report as well.
    XCTAssertNoThrow(try ReportWireInput.validateLocal(input))
    let local = LocalReportGenerator().make(input)
    XCTAssertEqual(local.observations.count, 3)
    XCTAssertFalse(local.recommendations.isEmpty)
  }
  func testActualSourceBearingReasonIDsAreMappedAndRestoredWithValuesAndActions() async throws {
    var input = try await freshPreparedInput()
    let sourceFacts = try [HealthDataType.restingHeartRate, .heartRateVariabilitySDNN].map { type in
      try XCTUnwrap(input.facts.first { $0.id.contains("|") && $0.metric == type.rawValue })
    }
    XCTAssertEqual(sourceFacts.count, 2)
    input.candidates[0].reasonFactIDs = sourceFacts.map(\.id)
    let wire = try ReportWireInput(input)
    XCTAssertEqual(wire.facts.count, 49)
    XCTAssertEqual(wire.candidates[0].reasonFactIDs.count, 2)
    var result = remoteResult(wire.validationInput)
    result.observations = try wire.candidates[0].reasonFactIDs.map { id in
      let fact = try XCTUnwrap(wire.validationInput.facts.first { $0.id == id })
      return .init(text: ReportText.observation(fact), evidenceIDs: [id])
    }
    let decoded = try ReportResultValidator.decode(AIReportPolicy.encoder().encode(result), input: input, now: input.asOf)
    XCTAssertEqual(decoded.observations.map { $0.evidenceIDs[0] }, sourceFacts.map(\.id))
    XCTAssertEqual(decoded.recommendations[0].actionID, input.candidates[0].actionID)
    for (observation, fact) in zip(decoded.observations, sourceFacts) {
      XCTAssertEqual(observation.text, ReportText.observation(fact))
      XCTAssertFalse(ReportText.display(observation, facts: input.facts).contains("{{fact:"))
    }
    var invalid = result; invalid.observations[0].evidenceIDs = [sourceFacts.first!.id]
    XCTAssertThrowsError(try ReportResultValidator.decode(AIReportPolicy.encoder().encode(invalid), input: input, now: input.asOf))
    invalid = result; invalid.observations[0].text = "记录值：99。"
    XCTAssertThrowsError(try ReportResultValidator.decode(AIReportPolicy.encoder().encode(invalid), input: input, now: input.asOf))
    invalid = result; invalid.recommendations[0].actionID = "a99"
    XCTAssertThrowsError(try ReportResultValidator.decode(AIReportPolicy.encoder().encode(invalid), input: input, now: input.asOf))
    input.candidates[0].reasonFactIDs.append("missing-authoritative-reason")
    XCTAssertThrowsError(try ReportWireInput(input))
  }
  func testLargeFreshClosureStillDisplaysLocalFallbackWithoutAIReadsOrNetwork() async throws {
    let input = try await freshPreparedInput(), capture = try fixture()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let consent = try LocalConsentStore(url: folder.appendingPathComponent("consent.json"))
    try consent.grant(.healthData, version: LocalConsentStore.healthConsentVersion, at: input.asOf)
    let health = FixtureHealthDataProvider(scenario: .complete)
    health.snapshot = capture.healthSnapshot
    let builder = ReportSnapshotBuilder(
      repository: SwiftDataAnalysisRepository(container: try PersistenceController.makeContainer(inMemory: true)),
      health: health, consent: consent, trend: CapturedHealthTrend(),
      recovery: CapturedRecoveryCalculator(result: capture.recoveryResult), recommendations: FixtureRecommendationProvider())
    let service = AIReportService(builder: builder, consent: consent, healthData: nil,
      cache: try AIReportCache(url: folder.appendingPathComponent("reports.json"), allowHealthHistory: true))
    let result = await service.report(type: .today, window: capture.healthSnapshot.window,
      asOf: input.asOf, timeZone: TimeZone(secondsFromGMT: 0)!, localInput: input)
    XCTAssertTrue(result.report.isLocalFallback)
    XCTAssertEqual(result.input, input)
    XCTAssertEqual(result.report.observations.count, 3)
    XCTAssertEqual(health.freshRequests, 0)
    XCTAssertFalse(service.isRemoteAvailable)
  }
  func testActualFRestAndReduceCandidatesRetainConstraintsAndAllReasonFacts() throws {
    let capture = try fixture()
    XCTAssertEqual(capture.recommendationCommit, "274c82e89918e6d8e06aba3205798c16993ffdde")
    for scenario in ["rest", "reduce"] {
      let input = try XCTUnwrap(capture.recommendationInputs[scenario])
      let expected: RecommendationAction = scenario == "rest" ? .rest : .reduceSets
      let candidate = try XCTUnwrap(input.candidates.first { $0.action == expected })
      XCTAssertTrue(candidate.exclusionCodes.contains(scenario == "rest" ? "no_training_snapshot" : "no_load_increase"))
      let local = LocalReportGenerator().make(input)
      XCTAssertTrue(local.recommendations.contains { $0.actionID == candidate.actionID })
      let wire = try ReportWireInput(input)
      XCTAssertTrue(input.facts.contains { $0.window.end > input.asOf })
      XCTAssertTrue(wire.facts.allSatisfy { $0.window.end <= input.asOf })
      XCTAssertEqual(wire.candidates.count, input.candidates.count)
      XCTAssertEqual(wire.candidates.flatMap(\.reasonFactIDs).count, input.candidates.flatMap(\.reasonFactIDs).count)
      XCTAssertTrue(wire.candidates.flatMap(\.reasonFactIDs).allSatisfy(Set(wire.facts.map(\.id)).contains))
      let result = try ReportResultValidator.decode(AIReportPolicy.encoder().encode(remoteResult(wire.validationInput)), input: input, now: input.asOf)
      XCTAssertEqual(Set(result.recommendations.map(\.actionID)), Set(input.candidates.map(\.actionID)))
      XCTAssertTrue(result.recommendations.contains { $0.actionID == candidate.actionID && $0.text == ReportText.action(expected) })
      let encoded = String(decoding: try AIReportPolicy.encoder().encode(wire), as: UTF8.self)
      for value in [candidate.actionID, "exclusionCodes", "allowedParameters", "dependencies"] { XCTAssertFalse(encoded.contains(value)) }
    }
  }
  func testRequiredSummaryOverflowFailsInsteadOfSilentlyTruncatingReasons() throws {
    var input = try XCTUnwrap(fixture().recommendationInputs["rest"])
    let template = try XCTUnwrap(input.facts.first)
    input.facts = (0..<101).map { index in var fact = template; fact.id = "summary.\(index)"; return fact }
    input.candidates = [.init(actionID: "approved", action: .rest, muscleIDs: [], reasonFactIDs: ["summary.100"])]
    XCTAssertThrowsError(try ReportWireInput(input))
    XCTAssertNoThrow(try ReportWireInput.validateLocal(input))
    XCTAssertEqual(LocalReportGenerator().make(input).observations.first?.evidenceIDs, ["summary.100"])
  }
  func testRecommendationDayProjectionCannotAdmitFutureMeasurementsOrUnboundedWindows() throws {
    let input = try XCTUnwrap(fixture().recommendationInputs["rest"])
    let index = try XCTUnwrap(input.facts.firstIndex { $0.metric == "recommendation.selectedPlan" })
    var invalid = input
    invalid.facts[index].metric = "restingHeartRate"
    XCTAssertThrowsError(try ReportWireInput(invalid))
    invalid = input; invalid.facts[index].sources = [.manual]
    XCTAssertThrowsError(try ReportWireInput(invalid))
    invalid = input; invalid.facts[index].window.end = input.asOf.addingTimeInterval(48 * 3600)
    XCTAssertThrowsError(try ReportWireInput(invalid))
    invalid = input; invalid.facts[index].window.start = input.asOf.addingTimeInterval(3600)
    XCTAssertThrowsError(try ReportWireInput(invalid))
  }
  func testRealCandidateSnapshotUsesOpaqueReportIdentityAndContextInvalidatesPersistentCache() async throws {
    let captured = try XCTUnwrap(fixture().recommendationInputs["reduce"])
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let consent = try LocalConsentStore(url: folder.appendingPathComponent("consent.json"))
    try consent.grant(.aiReports, version: LocalConsentStore.aiConsentVersion, at: captured.asOf)
    let health = FixtureHealthDataProvider(scenario: .manualOnly)
    let recommendations = CapturedRecommendationProvider(.init(candidates: captured.candidates,
      facts: captured.facts, contextFingerprint: "synthetic-plan-v1-days-1-3-5"))
    let builder = ReportSnapshotBuilder(
      repository: SwiftDataAnalysisRepository(container: try PersistenceController.makeContainer(inMemory: true)),
      health: health, consent: consent, trend: FixtureTrendCalculator(),
      recovery: FixtureRecoveryCalculator(), recommendations: recommendations)
    func prepare() async throws -> ReportInput {
      try await builder.prepare(type: .today, window: health.snapshot.window, asOf: captured.asOf,
        timeZone: TimeZone(secondsFromGMT: 0)!, knowledgeVersion: AIReportPolicy.knowledgeVersion,
        consentVersion: LocalConsentStore.aiConsentVersion).input
    }
    let first = try await prepare()
    XCTAssertEqual(first.candidates, captured.candidates)
    XCTAssertEqual(Set(first.facts.map(\.id)), Set(captured.facts.map(\.id)))
    XCTAssertNotEqual(first.inputFingerprint, recommendations.analysisFingerprints[0])
    let wire = try ReportWireInput(first)
    let decoded = try ReportResultValidator.decode(AIReportPolicy.encoder().encode(remoteResult(wire.validationInput)), input: first, now: first.asOf)
    let cacheURL = folder.appendingPathComponent("reports.json")
    let cache = try AIReportCache(url: cacheURL, allowHealthHistory: false)
    try cache.save(.init(report: decoded, input: first, dependsOnHealth: false))
    let same = try await prepare()
    XCTAssertEqual(same.inputFingerprint, first.inputFingerprint)
    XCTAssertNotNil(try cache.current(same, now: same.asOf))
    recommendations.value.contextFingerprint = "synthetic-plan-v2-days-2-4-6"
    let changed = try await prepare()
    XCTAssertEqual(recommendations.analysisFingerprints.count, 3)
    XCTAssertEqual(Set(recommendations.analysisFingerprints).count, 1)
    XCTAssertEqual(first.facts, changed.facts); XCTAssertEqual(first.candidates, changed.candidates)
    XCTAssertNotEqual(first.inputFingerprint, changed.inputFingerprint)
    XCTAssertThrowsError(try ReportResultValidator.validate(decoded, input: changed, now: changed.asOf))
    XCTAssertNil(try cache.current(changed, now: changed.asOf))
    let reopened = try AIReportCache(url: cacheURL, allowHealthHistory: false)
    XCTAssertNil(try reopened.current(changed, now: changed.asOf))
    XCTAssertEqual(reopened.history().first?.input.inputFingerprint, first.inputFingerprint)
    XCTAssertEqual(health.freshRequests, 3)
  }
}
