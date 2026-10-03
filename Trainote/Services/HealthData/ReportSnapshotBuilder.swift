import Foundation

struct PreparedReportInput {
  var input: ReportInput
  var aiConsent: ConsentLease
  var healthConsent: ConsentLease?
}

private struct ReportFingerprint: Encodable {
  /// Contains the original analysis fingerprint plus all prepared report output identity.
  var report: ReportInput
  var recommendationContextFingerprint: String?
}

/// Rebuild the entire dependency graph from a fresh readable window. Never accepts cached results.
@MainActor
final class ReportSnapshotBuilder {
  let repository: any AnalysisRepository
  let health: any HealthDataProviding
  let consent: any ConsentManaging
  let trend: any TrendCalculating
  let recovery: any RecoveryCalculating
  let recommendations: any RecommendationProviding

  init(
    repository: any AnalysisRepository, health: any HealthDataProviding,
    consent: any ConsentManaging,
    trend: any TrendCalculating, recovery: any RecoveryCalculating,
    recommendations: any RecommendationProviding
  ) {
    self.repository = repository
    self.health = health
    self.consent = consent
    self.trend = trend
    self.recovery = recovery
    self.recommendations = recommendations
  }
  func prepare(
    type: ReportType, window: AnalysisWindow, asOf: Date, timeZone: TimeZone,
    knowledgeVersion: String, consentVersion: String
  ) async throws -> PreparedReportInput {
    let aiLease = try consent.lease(for: .aiReports, version: consentVersion)
    let healthLease = try? consent.lease(
      for: .healthData, version: LocalConsentStore.healthConsentVersion)
    let current = try await health.freshSnapshot(window: window, timeZone: timeZone)
    try consent.validate(aiLease)
    if let healthLease { try consent.validate(healthLease) }
    guard current.isFresh, current.window == window,
      healthLease != nil || (current.samples.isEmpty && current.activityFacts.isEmpty)
    else { throw AnalysisFailure.staleSnapshot }
    let input = try repository.analysisInput(
      asOf: asOf, window: window, timeZone: timeZone, health: current)
    let trendResult = try trend.calculate(input)
    let recoveryResult = try recovery.calculate(input)
    guard trendResult.inputFingerprint == input.inputFingerprint,
      recoveryResult.inputFingerprint == input.inputFingerprint
    else { throw AnalysisFailure.staleSnapshot }
    let recommendationSnapshot = try recommendations.snapshot(
      input: input, trend: trendResult, recovery: recoveryResult)
    let candidates = recommendationSnapshot.candidates
    var factsByID: [String: MetricFact] = [:]
    for fact in input.health.facts + trendResult.facts + recoveryResult.facts
      + recommendationSnapshot.facts
    {
      if let old = factsByID[fact.id], old != fact { throw AnalysisFailure.invalidInput }
      factsByID[fact.id] = fact
    }
    let readableIDs = Set(current.samples.map { $0.id.uuidString })
    func dependencies(_ id: String, path: Set<String> = []) throws -> [SourceDependency] {
      guard !path.contains(id), let fact = factsByID[id] else { throw AnalysisFailure.invalidInput }
      var resolved: [SourceDependency] = []
      for dependency in fact.dependencies {
        switch dependency.kind {
        case .metricFact:
          resolved += try dependencies(dependency.id, path: path.union([id]))
        case .healthSample:
          guard readableIDs.contains(dependency.id) else { throw AnalysisFailure.staleSnapshot }
          resolved.append(dependency)
        case .manualRecord: resolved.append(dependency)
        }
      }
      guard
        !fact.sources.contains(where: { $0.kind == .healthKit })
          || resolved.contains(where: { $0.kind == .healthSample })
      else { throw AnalysisFailure.staleSnapshot }
      return Array(Set(resolved)).sorted {
        ($0.kind.rawValue, $0.id, $0.healthType?.rawValue ?? "")
          < ($1.kind.rawValue, $1.id, $1.healthType?.rawValue ?? "")
      }
    }
    let resultFacts: [MetricFact]
    switch type {
    case .trend: resultFacts = trendResult.facts
    case .recovery: resultFacts = recoveryResult.facts
    case .today, .weekly: resultFacts = trendResult.facts + recoveryResult.facts
    }
    var needed = Set(
      (resultFacts + recommendationSnapshot.facts).map(\.id) + candidates.flatMap(\.reasonFactIDs))
    for candidate in candidates {
      needed.formUnion(candidate.dependencies.filter { $0.kind == .metricFact }.map(\.id))
    }
    // Recursively include referenced facts; the transport never needs the full raw input.
    var frontier = Array(needed)
    while let id = frontier.popLast() {
      guard let fact = factsByID[id] else { throw AnalysisFailure.invalidInput }
      for dependency in fact.dependencies where dependency.kind == .metricFact {
        if needed.insert(dependency.id).inserted { frontier.append(dependency.id) }
      }
    }
    let facts = try needed.sorted().map { id -> MetricFact in
      var fact = factsByID[id]!
      fact.dependencies = try dependencies(id)
      return fact
    }
    for candidate in candidates {
      for dependency in candidate.dependencies {
        if dependency.kind == .healthSample && !readableIDs.contains(dependency.id) {
          throw AnalysisFailure.staleSnapshot
        }
        if dependency.kind == .metricFact { _ = try dependencies(dependency.id) }
      }
    }
    var report = ReportInput(
      reportType: type, asOf: asOf, inputFingerprint: input.inputFingerprint,
      facts: facts, candidates: candidates, goalDirection: input.profile?.goalDirection,
      knowledgeVersion: knowledgeVersion,
      calculationVersions: [trendResult.calculationVersion, recoveryResult.calculationVersion],
      missingData: current.statuses.filter { $0.state != .samplesAvailable }.map {
        $0.type.rawValue
      })
    // Calculator matching above uses the original AnalysisInput fingerprint. Only the final
    // report identity includes recommendation context/output, so changing a plan or schedule
    // invalidates cached reports without altering B/C's calculation contract.
    report.inputFingerprint = try AnalysisFingerprint.digest(
      ReportFingerprint(
        report: report, recommendationContextFingerprint: recommendationSnapshot.contextFingerprint))
    let prepared = PreparedReportInput(
      input: report, aiConsent: aiLease, healthConsent: healthLease)
    try validateBeforeSending(prepared)
    return prepared
  }
  /// E must call immediately before every send/retry, and cancel jobs on LocalConsentStore.onRevocation.
  func validateBeforeSending(_ prepared: PreparedReportInput) throws {
    try consent.validate(prepared.aiConsent)
    if let healthConsent = prepared.healthConsent { try consent.validate(healthConsent) }
  }
}
