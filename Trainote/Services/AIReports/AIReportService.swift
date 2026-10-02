import Foundation
import Observation

@MainActor
protocol AIReportTransport: AnyObject {
  var revocationPending: Bool { get }
  func generate(_ input: ReportInput, requestID: UUID, consent: ConsentLease,
    grantedAt: Date, beforeSending: @escaping @MainActor () throws -> Void) async throws -> ReportResult
  func cancelAndMarkRevocation() throws
  func revokeServerConsent() async throws
}

/// Implements the shared protocol, scoped to one freshly prepared input and revocable send lease.
@MainActor
private struct PreparedReportGenerator: ReportGenerating {
  let input: ReportInput
  let requestID: UUID
  let consent: ConsentLease
  let grantedAt: Date
  let transport: any AIReportTransport
  let beforeSending: @MainActor () throws -> Void
  func generate(_ input: ReportInput) async throws -> ReportResult {
    guard input == self.input else { throw AIReportFailure.invalidInput }
    try beforeSending()
    return try await transport.generate(input, requestID: requestID, consent: consent,
      grantedAt: grantedAt, beforeSending: beforeSending)
  }
}

/// F owns app assembly. Construct once, before displaying/caching reports, and keep for the app lifetime.
@MainActor
@Observable
final class AIReportService: HealthDerivedDataInvalidating {
  private let builder: ReportSnapshotBuilder
  private let consent: LocalConsentStore
  private let cache: AIReportCache
  private let transport: (any AIReportTransport)?
  private let clock: () -> Date
  private var generation = UUID()
  private var handlers: [UUID] = []
  private var active: (key: String, id: UUID, task: Task<AIReportContent, Never>)?
  private(set) var latest: AIReportContent?
  private(set) var failure: AIReportFailure?
  var isGenerating: Bool { active != nil }
  var isRemoteAvailable: Bool { transport != nil }
  var revocationPending: Bool { transport?.revocationPending ?? false }

  init(builder: ReportSnapshotBuilder, consent: LocalConsentStore, healthData: HealthDataService?,
    cache: AIReportCache, transport: (any AIReportTransport)? = nil, clock: @escaping () -> Date = { .now }) {
    self.builder = builder
    self.consent = consent
    self.cache = cache
    self.transport = transport
    self.clock = clock
    // Register actual persistent AND in-memory stores. Explicit disconnect invokes both.
    healthData?.addDerivedDataInvalidator(cache)
    healthData?.addDerivedDataInvalidator(self)
    handlers.append(consent.onRevocation(.aiReports) { [weak self] in
      guard let self else { return }
      self.cancelActive()
      self.latest = nil // Historical reports remain accessible only through the read-only history API.
      do { try self.transport?.cancelAndMarkRevocation() }
      catch { self.failure = .storage }
      // Direct LocalConsentStore revocation also starts server removal; F awaits closeAI for its result.
      Task { @MainActor [weak self] in try? await self?.resumePendingRevocation() }
    })
    handlers.append(consent.onRevocation(.healthData) { [weak self] in
      self?.cancelActive()
      if self?.latest?.dependsOnHealth == true { self?.latest = nil }
    })
    // Reconcile after a restart even if persisting the previous revocation marker failed.
    let record = consent.record(for: .aiReports)
    if record?.isGranted != true || record?.version != LocalConsentStore.aiConsentVersion {
      do { try transport?.cancelAndMarkRevocation() } catch { failure = .storage }
    }
  }

  /// localInput is only for immediate offline fallback. It is NEVER sent to the proxy.
  func report(type: ReportType, window: AnalysisWindow, asOf: Date, timeZone: TimeZone,
    localInput: ReportInput? = nil) async -> AIReportContent {
    let fallback = safeLocalInput(localInput, type: type, asOf: asOf)
    guard !Task.isCancelled else { return localContent(fallback) }
    guard let transport, let record = consent.record(for: .aiReports), record.isGranted,
      record.version == LocalConsentStore.aiConsentVersion else {
      failure = transport == nil ? .unavailable : .consentRequired
      let content = localContent(fallback); latest = content; return content
    }
    guard !transport.revocationPending else {
      failure = .revocationPending
      let content = localContent(fallback); latest = content; return content
    }
    let key = "\(type.rawValue)|\(window.start.timeIntervalSince1970)|\(window.end.timeIntervalSince1970)|\(asOf.timeIntervalSince1970)|\(timeZone.identifier)"
    if let active {
      // Coalesce identical requests; don't queue different reports behind an in-flight upload.
      if active.key == key { return await active.task.value }
      return localContent(fallback)
    }
    let requestID = UUID(), capturedGeneration = generation
    let task = Task { @MainActor [self] in
      do {
        // Each new request/retry rebuilds from HealthKit. An old prepared snapshot is never accepted.
        let prepared = try await builder.prepare(type: type, window: window, asOf: asOf,
          timeZone: timeZone, knowledgeVersion: AIReportPolicy.knowledgeVersion,
          consentVersion: LocalConsentStore.aiConsentVersion)
        let preparedAt = clock()
        let guardSend: @MainActor () throws -> Void = { [self] in
          try Task.checkCancellation()
          guard generation == capturedGeneration else { throw AIReportFailure.cancelled }
          try builder.validateBeforeSending(prepared)
          guard clock().timeIntervalSince(preparedAt) <= AIReportPolicy.maximumPreparedAge,
            prepared.input.asOf <= clock().addingTimeInterval(60),
            clock().timeIntervalSince(prepared.input.asOf) <= AIReportPolicy.maximumInputAge
          else { throw AIReportFailure.stale }
        }
        try guardSend()
        if let cached = try cache.current(prepared.input, now: clock()) { failure = nil; return cached }
        let generator = PreparedReportGenerator(input: prepared.input, requestID: requestID,
          consent: prepared.aiConsent, grantedAt: record.grantedAt!, transport: transport, beforeSending: guardSend)
        let result = try await generator.generate(prepared.input)
        try guardSend()
        try ReportResultValidator.validate(result, input: prepared.input, now: clock())
        let content = AIReportContent(report: result, input: prepared.input,
          dependsOnHealth: Self.dependsOnHealth(prepared.input))
        try cache.save(content)
        failure = nil
        return content
      } catch {
        if generation == capturedGeneration {
          failure = error as? AIReportFailure ?? (Task.isCancelled ? .cancelled : .unavailable)
        }
        // After disconnect, discard health-derived local inputs as well as the remote result.
        return localContent(generation == capturedGeneration ? fallback : safeLocalInput(nil, type: type, asOf: asOf))
      }
    }
    active = (key, requestID, task)
    let content = await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
    if active?.id == requestID { active = nil }
    if generation == capturedGeneration { latest = content }
    return content
  }

  func cancelActive() {
    generation = UUID()
    active?.task.cancel()
    active = nil
  }
  func closeAI() async throws {
    var localFailure: Error?
    do { try consent.revoke(.aiReports, at: clock()) } catch { localFailure = error }
    // Hook above already cancels synchronously, before the first network await.
    try await resumePendingRevocation()
    if let localFailure { throw localFailure }
  }
  /// F calls at foreground/startup. Only revocation is retried; no reports run in background.
  func resumePendingRevocation() async throws {
    guard transport?.revocationPending == true else { return }
    try await transport?.revokeServerConsent()
  }
  func deleteAIReports() throws {
    cancelActive(); latest = nil
    try cache.deleteAll()
  }
  func deleteHealthDependentData() throws {
    cancelActive()
    if latest?.dependsOnHealth == true { latest = nil }
  }
  func history() -> [AIReportContent] { cache.history() }
  private func localContent(_ input: ReportInput) -> AIReportContent {
    .init(report: LocalReportGenerator().make(input), input: input, dependsOnHealth: Self.dependsOnHealth(input))
  }
  private func safeLocalInput(_ input: ReportInput?, type: ReportType, asOf: Date) -> ReportInput {
    if let input, input.reportType == type, abs(input.asOf.timeIntervalSince(asOf)) < 1,
      (!Self.dependsOnHealth(input) || consent.record(for: .healthData)?.isGranted == true),
      (try? ReportWireInput(input)) != nil { return input }
    return .init(reportType: type, asOf: asOf, inputFingerprint: String(repeating: "0", count: 64),
      facts: [], candidates: [], goalDirection: nil, knowledgeVersion: AIReportPolicy.knowledgeVersion,
      calculationVersions: ["unavailable"], missingData: ["records"])
  }
  private static func dependsOnHealth(_ input: ReportInput) -> Bool {
    input.facts.contains { $0.sources.contains { $0.kind == .healthKit } || $0.dependencies.contains { $0.kind == .healthSample } }
      || input.candidates.contains { $0.dependencies.contains { $0.kind == .healthSample } }
  }
}
