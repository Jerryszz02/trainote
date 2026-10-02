import Foundation
import Observation

/// ReportSnapshotBuilder calls this synchronously on its main actor, after its fresh read.
/// Keeping the bridge alive does not freeze the selected template at app startup.
struct CurrentTrainingReportRecommendations: RecommendationProviding {
  let controller: TrainingAdviceController

  func candidates(input: AnalysisInput, trend: TrendResult, recovery: RecoveryResult) throws
    -> [RecommendationCandidate]
  {
    try snapshot(input: input, trend: trend, recovery: recovery).candidates
  }

  func snapshot(input: AnalysisInput, trend: TrendResult, recovery: RecoveryResult) throws
    -> RecommendationSnapshot
  {
    try MainActor.assumeIsolated {
      try controller.makeRecommendationProvider().snapshot(
        input: input, trend: trend, recovery: recovery)
    }
  }
}

/// F's app-lifetime adapter owns navigation state; E owns report storage and revocation.
@MainActor
@Observable
final class HealthReportIntegration: AIReportLifecycle {
  let foundation: HealthFoundation
  let trend: any TrendCalculating
  let recovery: RecoveryService?
  let advice: TrainingAdviceController
  let service: AIReportService?
  let consentVersion = LocalConsentStore.aiConsentVersion
  private(set) var errorMessage: String?
  private(set) var isRefreshing = false
  private var fallback: AIReportContent?
  private var displayedSelection: String?
  private var generation = UUID()
  private var historyRevision = 0

  init(
    foundation: HealthFoundation, trend: any TrendCalculating, recovery: RecoveryService?,
    advice: TrainingAdviceController, directory: URL
  ) {
    self.foundation = foundation
    self.trend = trend
    self.recovery = recovery
    self.advice = advice
    if let recovery {
      do {
        service = try AIReportAssembly.make(
          foundation: foundation, trend: trend, recovery: recovery,
          recommendations: CurrentTrainingReportRecommendations(controller: advice),
          proxy: nil, directory: directory)
      } catch { service = nil }
    } else {
      service = nil
    }
  }

  var isConfigured: Bool { service?.isRemoteAvailable == true }
  var serverRevocationPending: Bool { service?.revocationPending == true }
  var configurationMessage: String {
    "AI 报告尚未开放。完成代理配置、设备认证及 DeepSeek API 数据处理条款核验后，才能单独选择启用。目前可查看本地基础报告。"
  }
  var content: AIReportContent? {
    guard let displayedSelection, displayedSelection == (try? selectionIdentity()) else {
      return nil
    }
    if let service { return service.latest }
    return fallback
  }
  var history: [AIReportContent] {
    _ = historyRevision
    return service?.history() ?? []
  }

  /// A new explicit refresh fixes one evaluation time; SwiftUI recomputation never changes it.
  func refresh(type: ReportType, asOf: Date = .now, timeZone: TimeZone = .current) async {
    if isRefreshing { service?.cancelActive() }
    isRefreshing = true
    errorMessage = nil
    let request = UUID()
    generation = request
    defer { if generation == request { isRefreshing = false } }
    do {
      do { try await resumePendingRevocation() } catch {
        errorMessage = "AI 撤回尚未完成；当前显示本地基础报告，请在设置中重试撤回。"
      }
      try Task.checkCancellation()
      let selection = try selectionIdentity()
      let window = AnalysisWindow(
        start: asOf.addingTimeInterval(-Double(RecoveryParameters.inputDays) * 86_400), end: asOf)
      let localInput = try localReportInput(
        type: type, window: window, asOf: asOf, timeZone: timeZone)
      if let service {
        _ = await service.report(
          type: type, window: window, asOf: asOf, timeZone: timeZone, localInput: localInput)
      } else {
        fallback = AIReportContent(
          report: LocalReportGenerator().make(localInput), input: localInput,
          dependsOnHealth: localInput.facts.contains {
            $0.sources.contains { $0.kind == .healthKit }
              || $0.dependencies.contains { $0.kind == .healthSample }
          })
      }
      guard generation == request else { return }
      try Task.checkCancellation()
      guard selection == (try? selectionIdentity()) else { throw AnalysisFailure.staleSnapshot }
      displayedSelection = selection
      historyRevision += 1
    } catch {
      guard generation == request else { return }
      displayedSelection = nil
      fallback = nil
      errorMessage =
        serverRevocationPending
        ? "AI 撤回尚未完成，请在设置中重试。训练、饮食和本地分析仍可使用。"
        : "记录或模板已变化，或暂时无法读取。请刷新报告后重试。"
    }
  }

  /// Local fallback uses current repository/calculators and is never handed to a transport.
  /// Remote reports always use E's fresh A builder, including its verified dependency closure.
  func localReportInput(
    type: ReportType, window: AnalysisWindow, asOf: Date, timeZone: TimeZone
  ) throws -> ReportInput {
    guard let recovery else { throw AnalysisFailure.unavailable }
    let health =
      try foundation.healthData?.localSnapshot(window: window)
      ?? .disconnected(window: window, asOf: asOf)
    let input = try foundation.repository.analysisInput(
      asOf: asOf, window: window, timeZone: timeZone, health: health)
    let trendResult = try trend.calculate(input)
    let recoveryResult = try recovery.calculate(input)
    let recommendations = try advice.makeRecommendationProvider().snapshot(
      input: input, trend: trendResult, recovery: recoveryResult)
    var factsByID: [String: MetricFact] = [:]
    for fact in input.health.facts + trendResult.facts + recoveryResult.facts
      + recommendations.facts
    {
      if let old = factsByID[fact.id], old != fact { throw AnalysisFailure.invalidInput }
      factsByID[fact.id] = fact
    }
    let analyticalFacts: [MetricFact]
    switch type {
    case .trend: analyticalFacts = trendResult.facts
    case .recovery: analyticalFacts = recoveryResult.facts
    case .today, .weekly: analyticalFacts = trendResult.facts + recoveryResult.facts
    }
    var needed = Set(
      (analyticalFacts + recommendations.facts).map(\.id)
        + recommendations.candidates.flatMap(\.reasonFactIDs))
    var frontier = Array(needed)
    while let id = frontier.popLast() {
      guard let fact = factsByID[id] else { throw AnalysisFailure.invalidInput }
      for dependency in fact.dependencies where dependency.kind == .metricFact {
        if needed.insert(dependency.id).inserted { frontier.append(dependency.id) }
      }
    }
    var report = ReportInput(
      reportType: type, asOf: asOf, inputFingerprint: input.inputFingerprint,
      facts: needed.sorted().compactMap { factsByID[$0] }, candidates: recommendations.candidates,
      goalDirection: input.profile?.goalDirection,
      knowledgeVersion: AIReportPolicy.knowledgeVersion,
      calculationVersions: [trendResult.calculationVersion, recoveryResult.calculationVersion],
      missingData: health.statuses.filter { $0.state != .samplesAvailable }.map { $0.type.rawValue }
    )
    report.inputFingerprint = try AnalysisFingerprint.digest(
      LocalReportIdentity(
        report: report, contextFingerprint: recommendations.contextFingerprint))
    try ReportWireInput.validateLocal(report)
    return report
  }

  private func selectionIdentity() throws -> String {
    let current = try advice.makeRecommendationProvider()
    return TrainingRecommendationContext(
      selectedPlan: current.selectedPlan, alternativePlans: current.alternativePlans,
      availableWeekdays: current.availableWeekdays, exerciseMuscles: current.exerciseMuscles
    ).fingerprint
  }

  func activateConsent() async throws {
    guard isConfigured else { throw AnalysisFailure.unavailable }
    try await resumePendingRevocation()
  }
  func cancelPendingRequests() {
    generation = UUID()
    isRefreshing = false
    service?.cancelActive()
    displayedSelection = nil
    fallback = nil
  }
  func revokeServerConsent() async throws { try await resumePendingRevocation() }
  func closeAI(at date: Date, consent: LocalConsentStore?) async throws {
    cancelPendingRequests()
    if let service {
      try await service.closeAI()
    } else {
      guard let consent else { throw AnalysisFailure.storageFailed }
      try consent.revoke(.aiReports, at: date)
    }
    historyRevision += 1
  }
  func resumePendingRevocation() async throws { try await service?.resumePendingRevocation() }
  func deleteAllReports() throws {
    cancelPendingRequests()
    defer { historyRevision += 1 }
    guard let service else { throw AnalysisFailure.storageFailed }
    try service.deleteAIReports()
  }
  func deleteHealthDependentData() throws {
    generation = UUID()
    isRefreshing = false
    if fallback?.dependsOnHealth == true {
      fallback = nil
      displayedSelection = nil
    }
    historyRevision += 1
  }
}

private struct LocalReportIdentity: Encodable {
  let report: ReportInput
  let contextFingerprint: String?
}
