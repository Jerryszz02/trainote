import SwiftData
import XCTest

@testable import Trainote

private final class SnapshotRecommendationProvider: RecommendationProviding {
  var value: RecommendationSnapshot
  private(set) var snapshotRequests = 0
  private(set) var candidateRequests = 0

  init(_ value: RecommendationSnapshot) { self.value = value }

  func candidates(input: AnalysisInput, trend: TrendResult, recovery: RecoveryResult) throws
    -> [RecommendationCandidate]
  {
    candidateRequests += 1
    return value.candidates
  }

  func snapshot(input: AnalysisInput, trend: TrendResult, recovery: RecoveryResult) throws
    -> RecommendationSnapshot
  {
    snapshotRequests += 1
    return value
  }
}

private struct RecommendationFactsTrend: TrendCalculating {
  var facts: [MetricFact]
  var fingerprintOverride: String? = nil
  func calculate(_ input: AnalysisInput) throws -> TrendResult {
    var result = try FixtureTrendCalculator().calculate(input)
    result.facts = facts
    result.inputFingerprint = fingerprintOverride ?? input.inputFingerprint
    return result
  }
}

@MainActor
final class RecommendationSnapshotTests: XCTestCase {
  private var directory: URL!
  override func setUp() {
    super.setUp()
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }
  override func tearDown() {
    try? FileManager.default.removeItem(at: directory)
    super.tearDown()
  }

  func testCandidateOnlyProviderUsesCompatibleDefaultSnapshot() async throws {
    let provider: any RecommendationProviding = FixtureRecommendationProvider()
    let input = AnalysisFixtures.input()
    let snapshot = try provider.snapshot(
      input: input, trend: AnalysisFixtures.trend, recovery: AnalysisFixtures.recovery)
    XCTAssertEqual(snapshot.candidates, AnalysisFixtures.report.candidates)
    XCTAssertTrue(snapshot.facts.isEmpty)
    XCTAssertNil(snapshot.contextFingerprint)
    XCTAssertEqual(
      try JSONDecoder().decode(RecommendationSnapshot.self, from: JSONEncoder().encode(snapshot)),
      snapshot)
    let builder = try makeBuilder(provider)
    let prepared = try await prepare(builder)
    XCTAssertEqual(prepared.input.candidates, snapshot.candidates)
  }

  func testSnapshotCollectsSelectedPlanFactsAndCandidateOnlyDependenciesOnce() async throws {
    let context = fact("recommendation.context", dependencies: [
      .init(kind: .manualRecord, id: "template.revision.1")
    ])
    let selectedPlan = fact("recommendation.selectedPlan", dependencies: [
      .init(kind: .metricFact, id: context.id)
    ])
    let availableDays = fact("recommendation.availableDays", dependencies: [
      .init(kind: .manualRecord, id: "training-days.1-3-5")
    ])
    var planCandidate = candidate(reason: selectedPlan.id)
    planCandidate.dependencies = [.init(kind: .metricFact, id: availableDays.id)]
    let provider = SnapshotRecommendationProvider(
      .init(candidates: [planCandidate], facts: [selectedPlan, context], contextFingerprint: "plan-v1"))
    // Recovery reports do not ordinarily include trend facts. A direct candidate dependency must
    // still include its fact and dependency closure even when it is absent from reasonFactIDs.
    let builder = try makeBuilder(provider, trend: RecommendationFactsTrend(facts: [availableDays]))
    let prepared = try await prepare(builder, type: .recovery)
    XCTAssertEqual(provider.snapshotRequests, 1)
    XCTAssertEqual(provider.candidateRequests, 0)
    XCTAssertEqual(Set(prepared.input.facts.map(\.id)), Set([selectedPlan.id, context.id, availableDays.id]))
    XCTAssertEqual(prepared.input.candidates, [planCandidate])
    XCTAssertEqual(
      prepared.input.facts.first { $0.id == selectedPlan.id }?.dependencies,
      [.init(kind: .manualRecord, id: "template.revision.1")])
    XCTAssertEqual(
      try JSONDecoder().decode(RecommendationSnapshot.self, from: JSONEncoder().encode(provider.value)),
      provider.value)
  }

  func testTemplateRevisionAndAvailableDaysIndependentlyInvalidateReportFingerprint() async throws {
    let provider = SnapshotRecommendationProvider(
      .init(candidates: [candidate()], facts: [fact()],
        contextFingerprint: try contextFingerprint(templateRevision: 1, days: [1, 3, 5])))
    let builder = try makeBuilder(provider)
    let initial = try await prepare(builder)
    let repeated = try await prepare(builder)
    XCTAssertEqual(initial.input, repeated.input)
    provider.value.contextFingerprint = try contextFingerprint(templateRevision: 2, days: [1, 3, 5])
    let newTemplate = try await prepare(builder)
    XCTAssertEqual(newTemplate.input.facts, initial.input.facts)
    XCTAssertEqual(newTemplate.input.candidates, initial.input.candidates)
    XCTAssertNotEqual(newTemplate.input.inputFingerprint, initial.input.inputFingerprint)
    provider.value.contextFingerprint = try contextFingerprint(templateRevision: 2, days: [2, 4, 6])
    let newDays = try await prepare(builder)
    XCTAssertNotEqual(newDays.input.inputFingerprint, newTemplate.input.inputFingerprint)
    let repeatedDays = try await prepare(builder)
    XCTAssertEqual(newDays.input.inputFingerprint, repeatedDays.input.inputFingerprint)
  }

  func testFingerprintIncludesReportOutputIdentityWithStableFactOrdering() async throws {
    let provider = SnapshotRecommendationProvider(
      .init(candidates: [candidate()], facts: [fact(), fact("recommendation.availableDays")],
        contextFingerprint: "stable-context"))
    let builder = try makeBuilder(provider)
    let first = try await prepare(builder)
    provider.value.facts.reverse()
    let reordered = try await prepare(builder)
    XCTAssertEqual(first.input, reordered.input)
    provider.value.facts[0].value = 4
    let changedFact = try await prepare(builder)
    XCTAssertNotEqual(first.input.inputFingerprint, changedFact.input.inputFingerprint)
    provider.value.candidates[0].allowedParameters = [
      .init(name: "setCount", minimum: 2, maximum: 4, unit: .count)
    ]
    let changedCandidate = try await prepare(builder)
    XCTAssertNotEqual(changedFact.input.inputFingerprint, changedCandidate.input.inputFingerprint)
    let changedType = try await prepare(builder, type: .weekly)
    XCTAssertNotEqual(changedCandidate.input.inputFingerprint, changedType.input.inputFingerprint)
  }

  func testMissingConflictingAndCyclicRecommendationFactsAreRejected() async throws {
    var missingDependency = candidate(reason: "")
    missingDependency.reasonFactIDs = []
    missingDependency.dependencies = [.init(kind: .metricFact, id: "missing.fact")]
    var conflicting = fact()
    conflicting.value = 99
    let cases: [(String, RecommendationSnapshot)] = [
      ("missing reason", .init(candidates: [candidate(reason: "missing.fact")])),
      ("missing candidate dependency", .init(candidates: [missingDependency])),
      ("missing fact dependency", .init(candidates: [candidate()], facts: [
        fact(dependencies: [.init(kind: .metricFact, id: "missing.fact")])
      ])),
      ("conflicting facts", .init(candidates: [candidate()], facts: [fact(), conflicting])),
      ("cycle", .init(candidates: [candidate()], facts: [
        fact(dependencies: [.init(kind: .metricFact, id: "recommendation.cycle")]),
        fact("recommendation.cycle", dependencies: [.init(kind: .metricFact, id: "recommendation.selectedPlan")]),
      ])),
      ("unreferenced invalid fact", .init(candidates: [], facts: [
        fact(dependencies: [.init(kind: .metricFact, id: "recommendation.selectedPlan")])
      ])),
    ]
    for (name, snapshot) in cases {
      let builder = try makeBuilder(SnapshotRecommendationProvider(snapshot))
      do {
        _ = try await prepare(builder)
        XCTFail("Expected invalidInput: \(name)")
      } catch { XCTAssertEqual(error as? AnalysisFailure, .invalidInput, name) }
    }
    let collision = try makeBuilder(
      SnapshotRecommendationProvider(.init(candidates: [candidate()], facts: [fact()])),
      trend: RecommendationFactsTrend(facts: [conflicting]))
    do {
      _ = try await prepare(collision)
      XCTFail("Expected a conflict with an existing calculator fact")
    } catch { XCTAssertEqual(error as? AnalysisFailure, .invalidInput) }
  }

  func testRecommendationHealthDependenciesMustRemainFreshAndConsentValid() async throws {
    let health = FixtureHealthDataProvider(scenario: .complete)
    let sample = try XCTUnwrap(health.snapshot.samples.first { $0.type == .heartRateVariabilitySDNN })
    var baseline = fact("recommendation.hrvBaseline", dependencies: [
      .init(kind: .healthSample, id: sample.id.uuidString, healthType: .heartRateVariabilitySDNN)
    ])
    baseline.sources = [sample.source.dataSource]
    let provider = SnapshotRecommendationProvider(
      .init(candidates: [candidate()], facts: [
        fact(dependencies: [.init(kind: .metricFact, id: baseline.id)]), baseline,
      ], contextFingerprint: "same-plan"))
    let builder = try makeBuilder(provider, health: health)
    let initial = try await prepare(builder)
    XCTAssertEqual(
      initial.input.facts.first { $0.id == "recommendation.selectedPlan" }?.dependencies,
      [.init(kind: .healthSample, id: sample.id.uuidString, healthType: .heartRateVariabilitySDNN)])
    // The provider still holds the old derived fact; a new system read no longer returns its sample.
    health.snapshot = AnalysisFixtures.health(.manualOnly)
    do {
      _ = try await prepare(builder)
      XCTFail("Expected staleSnapshot after the health dependency becomes unreadable")
    } catch { XCTAssertEqual(error as? AnalysisFailure, .staleSnapshot) }
    health.snapshot = AnalysisFixtures.health(.complete)
    provider.value.facts[1].dependencies = []
    do {
      _ = try await prepare(builder)
      XCTFail("Health-sourced facts require readable provenance")
    } catch { XCTAssertEqual(error as? AnalysisFailure, .staleSnapshot) }
    try builder.consent.revoke(.healthData, at: AnalysisFixtures.asOf)
    XCTAssertThrowsError(try builder.validateBeforeSending(initial)) {
      XCTAssertEqual($0 as? AnalysisFailure, .consentChanged)
    }
  }

  func testCalculatorMatchingStillUsesOriginalAnalysisFingerprint() async throws {
    let provider = SnapshotRecommendationProvider(.init(candidates: [], contextFingerprint: "plan-v1"))
    let builder = try makeBuilder(
      provider, trend: RecommendationFactsTrend(facts: [], fingerprintOverride: "stale-analysis"))
    do {
      _ = try await prepare(builder)
      XCTFail("Expected staleSnapshot for calculator output from a different input")
    } catch { XCTAssertEqual(error as? AnalysisFailure, .staleSnapshot) }
    XCTAssertEqual(provider.snapshotRequests, 0)
  }

  private func fact(
    _ id: String = "recommendation.selectedPlan", dependencies: [SourceDependency] = []
  ) -> MetricFact {
    .init(
      id: id, metric: id, value: 1, unit: .count, window: AnalysisFixtures.window,
      sources: [.init(kind: .calculation, identifier: "synthetic.training-rules", version: "1")],
      dependencies: dependencies)
  }

  private func candidate(reason: String = "recommendation.selectedPlan") -> RecommendationCandidate {
    .init(actionID: "plan.keep", action: .keepPlan, muscleIDs: [.chest], reasonFactIDs: [reason])
  }

  private func contextFingerprint(templateRevision: Int, days: [Int]) throws -> String {
    struct Context: Encodable { var templateRevision: Int; var days: [Int] }
    return try AnalysisFingerprint.digest(Context(templateRevision: templateRevision, days: days))
  }

  private func makeBuilder(
    _ recommendations: any RecommendationProviding,
    health: FixtureHealthDataProvider? = nil,
    trend: any TrendCalculating = FixtureTrendCalculator()
  ) throws -> ReportSnapshotBuilder {
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("\(UUID()).json"))
    try consent.grant(.aiReports, version: LocalConsentStore.aiConsentVersion, at: AnalysisFixtures.asOf)
    try consent.grant(.healthData, version: LocalConsentStore.healthConsentVersion, at: AnalysisFixtures.asOf)
    return ReportSnapshotBuilder(
      repository: SwiftDataAnalysisRepository(container: try PersistenceController.makeContainer(inMemory: true)),
      health: health ?? FixtureHealthDataProvider(scenario: .manualOnly),
      consent: consent, trend: trend, recovery: FixtureRecoveryCalculator(),
      recommendations: recommendations)
  }

  private func prepare(_ builder: ReportSnapshotBuilder, type: ReportType = .today) async throws
    -> PreparedReportInput
  {
    try await builder.prepare(
      type: type, window: AnalysisFixtures.window, asOf: AnalysisFixtures.asOf,
      timeZone: TimeZone(secondsFromGMT: 0)!, knowledgeVersion: "fixture",
      consentVersion: LocalConsentStore.aiConsentVersion)
  }
}
