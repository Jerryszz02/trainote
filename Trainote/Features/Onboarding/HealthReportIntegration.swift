import Foundation
import Observation
import SwiftData
import UIKit

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
  private(set) var errorMessageKey: String?
  private(set) var errorMessage: String? {
    get { errorMessageKey.map { L10n.text($0) } }
    set { errorMessageKey = newValue }
  }
  private(set) var isRefreshing = false
  private var fallback: AIReportContent?
  private var displayedSelection: String?
  private var generation = UUID()
  private var historyRevision = 0
  private var lastRequestedType: ReportType?
  private var lastInput: ReportInput?
  private var lastInputTimeZone: TimeZone = .current
  private var evaluationTime: Date?
  private(set) var processingAllowed = true
  private(set) var onDeviceAIEnabled = true
  var isGenerating: Bool { service?.isGenerating == true }
  var canGenerateOnDevice: Bool { processingAllowed && onDeviceAIEnabled && service?.isOnDeviceAvailable == true }
  @ObservationIgnored private var saveObserver: NSObjectProtocol?
  @ObservationIgnored private var resourceObservers: [NSObjectProtocol] = []

  init(
    foundation: HealthFoundation, trend: any TrendCalculating, recovery: RecoveryService?,
    advice: TrainingAdviceController, directory: URL,
    onDeviceRuntime: (any OnDeviceModelRuntime)? = BundledLlamaRuntime()
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
          proxy: nil, onDeviceRuntime: onDeviceRuntime, directory: directory)
      } catch { service = nil }
    } else {
      service = nil
    }
    saveObserver = NotificationCenter.default.addObserver(
      forName: ModelContext.didSave, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.cancelPendingRequests() }
    }
    advice.onSelectionChange = { [weak self] in self?.cancelPendingRequests() }
    for notification in [UIApplication.didReceiveMemoryWarningNotification,
                         ProcessInfo.thermalStateDidChangeNotification] {
      resourceObservers.append(NotificationCenter.default.addObserver(
        forName: notification, object: nil, queue: .main
      ) { [weak self] notice in
        MainActor.assumeIsolated {
          guard let self, self.isGenerating else { return }
          if notice.name == UIApplication.didReceiveMemoryWarningNotification
            || ProcessInfo.processInfo.thermalState == .serious
            || ProcessInfo.processInfo.thermalState == .critical {
            self.cancelGeneration()
            self.errorMessage = "localAI.report.fallback"
          }
        }
      })
    }
  }

  deinit {
    if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
    resourceObservers.forEach { NotificationCenter.default.removeObserver($0) }
  }

  var isConfigured: Bool { service?.isRemoteAvailable == true }
  var serverRevocationPending: Bool { service?.revocationPending == true }
  var configurationMessage: String {
    L10n.text("health.healthreportintegration.ai.reports.are.not.yet.available.e59eb3")
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
  func refresh(type: ReportType, asOf: Date? = nil, timeZone: TimeZone = .current) async {
    await prepare(type: type, asOf: asOf, timeZone: timeZone, generate: false)
  }

  func generateOnDevice(type: ReportType, asOf: Date? = nil, timeZone: TimeZone = .current) async {
    guard canGenerateOnDevice, !isGenerating else { return }
    await prepare(type: type, asOf: asOf, timeZone: timeZone, generate: true)
  }

  private func prepare(type: ReportType, asOf requestedTime: Date?, timeZone: TimeZone, generate: Bool) async {
    guard processingAllowed else { return }
    let now = Date.now
    let asOf = requestedTime ?? evaluationTime.flatMap {
      now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) < 300 ? $0 : nil
    } ?? now
    evaluationTime = asOf
    lastRequestedType = type
    if isRefreshing { service?.cancelActive() }
    isRefreshing = true
    errorMessage = nil
    let request = UUID()
    generation = request
    defer { if generation == request { isRefreshing = false } }
    do {
      do { try await resumePendingRevocation() } catch {
        errorMessage = "health.healthreportintegration.ai.withdrawal.is.incomplete.local.basic.f1d885"
      }
      try Task.checkCancellation()
      let selection = try selectionIdentity()
      let window = AnalysisWindow(
        start: asOf.addingTimeInterval(-Double(RecoveryParameters.inputDays) * 86_400), end: asOf)
      let localInput = try localReportInput(
        type: type, window: window, asOf: asOf, timeZone: timeZone)
      lastInput = localInput
      lastInputTimeZone = timeZone
      if let service {
        service.refreshOnDevice(localInput, allowAI: onDeviceAIEnabled)
        if generate {
          _ = await service.generateOnDevice(localInput) { [weak self] in
            guard let self, self.processingAllowed, self.onDeviceAIEnabled,
              self.generation == request, selection == (try? self.selectionIdentity())
            else { throw AIReportFailure.cancelled }
            let current = try self.localReportInput(type: type, window: window, asOf: asOf, timeZone: timeZone)
            guard current == localInput else { throw AIReportFailure.stale }
          }
          if service.failure != nil { errorMessage = "localAI.report.fallback" }
        }
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
        ? "health.healthreportintegration.ai.withdrawal.is.incomplete.retry.in.52139d"
        : "health.healthreportintegration.records.or.templates.changed.or.could.dca91e"
    }
  }

  /// Refresh an already requested basic report after foreground health synchronization.
  /// A configured remote service still requires the report page's explicit request path.
  func refreshLocalAfterHealthSync() async {
    guard processingAllowed else { return }
    evaluationTime = nil
    guard let lastRequestedType else { return }
    await refresh(type: lastRequestedType)
  }

  func setProcessingAllowed(_ allowed: Bool) {
    guard processingAllowed != allowed else { return }
    processingAllowed = allowed
    if !allowed { cancelPendingRequests(); service?.clearCurrent(); lastInput = nil }
  }

  func setOnDeviceAIEnabled(_ enabled: Bool) {
    guard onDeviceAIEnabled != enabled else { return }
    onDeviceAIEnabled = enabled
    cancelGeneration()
  }

  func cancelGeneration() {
    let input = lastInput
    let timeZone = lastInputTimeZone
    let previousEvaluation = evaluationTime
    cancelPendingRequests()
    if processingAllowed, let input {
      let window = AnalysisWindow(start: input.asOf.addingTimeInterval(-Double(RecoveryParameters.inputDays) * 86_400), end: input.asOf)
      if let current = try? localReportInput(type: input.reportType, window: window,
        asOf: input.asOf, timeZone: timeZone), current == input {
        lastInput = input
        evaluationTime = previousEvaluation
        service?.refreshOnDevice(input, allowAI: false)
        displayedSelection = try? selectionIdentity()
      }
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
    evaluationTime = nil
    lastInput = nil
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
  func deleteReport(id: String) throws {
    guard let service else { throw AnalysisFailure.storageFailed }
    try service.deleteReport(id: id)
    historyRevision += 1
  }
  func deleteHealthDependentData() throws {
    cancelPendingRequests()
    historyRevision += 1
  }
}

private struct LocalReportIdentity: Encodable {
  let report: ReportInput
  let contextFingerprint: String?
}
