import Foundation
import Observation

#if DEBUG
  /// Temporary, local UI-test diagnostics; never records health values or persists data.
  enum HealthUITestTrace {
    static func record(_ event: String, flags: [(String, Bool)] = []) {
      guard ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return }
      let time = String(format: "%.6f", ProcessInfo.processInfo.systemUptime)
      let phases = flags.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
      print("[health-ui] t=\(time) event=\(event) \(phases)")
    }
  }
#endif

/// E supplies this adapter when its verified implementation is installed.
/// Construction/availability inspection must never register consent or send health data.
@MainActor
protocol AIReportLifecycle: AnyObject, HealthDerivedDataInvalidating {
  var isConfigured: Bool { get }
  var consentVersion: String { get }
  var configurationMessage: String { get }
  var serverRevocationPending: Bool { get }
  func activateConsent() async throws
  func cancelPendingRequests()
  func revokeServerConsent() async throws
  func closeAI(at date: Date, consent: LocalConsentStore?) async throws
  func resumePendingRevocation() async throws
  func deleteAllReports() throws
}

extension AIReportLifecycle {
  func closeAI(at date: Date, consent: LocalConsentStore?) async throws {
    cancelPendingRequests()
    var localFailure: Error?
    do {
      guard let consent else { throw AnalysisFailure.storageFailed }
      try consent.revoke(.aiReports, at: date)
    } catch { localFailure = error }
    try await revokeServerConsent()
    if let localFailure { throw localFailure }
  }
  func resumePendingRevocation() async throws {
    if serverRevocationPending { try await revokeServerConsent() }
  }
}

@MainActor
@Observable
final class HealthFeatureAccess {
  let consent: LocalConsentStore?
  let health: (any HealthDataProviding)?
  let reports: any AIReportLifecycle
  private(set) var isBusy = false
  private(set) var isConnectingHealth = false
  private var showsConfigurationMessage = false
  private(set) var errorMessageKey: String?
  private(set) var errorMessage: String? {
    get { showsConfigurationMessage ? reports.configurationMessage : errorMessageKey.map { L10n.text($0) } }
    set { showsConfigurationMessage = false; errorMessageKey = newValue }
  }
  private(set) var statusMessageKey: String?
  private(set) var statusMessage: String? {
    get { statusMessageKey.map { L10n.text($0) } }
    set { statusMessageKey = newValue }
  }
  private(set) var healthDeletionNeedsRetry = false
  private(set) var aiRevocationNeedsRetry = false

  init(
    consent: LocalConsentStore?, health: (any HealthDataProviding)?,
    reports: any AIReportLifecycle,
    registerInvalidator: (any HealthDerivedDataInvalidating) -> Void
  ) {
    self.consent = consent
    self.health = health
    self.reports = reports
    // Install this before exposing any report UI. Revocation cancels synchronously.
    registerInvalidator(reports)
    consent?.onRevocation(.aiReports) { [weak reports] in reports?.cancelPendingRequests() }
  }

  convenience init(foundation: HealthFoundation, reports: any AIReportLifecycle) {
    self.init(consent: foundation.consent, health: foundation.healthData, reports: reports) {
      foundation.healthData?.addDerivedDataInvalidator($0)
    }
  }

  var healthConnected: Bool { consent?.record(for: .healthData)?.isGranted == true }
  /// The local consent means a request was made; HealthKit never reveals read permission.
  var healthConnectionLabel: String {
    if healthDeletionNeedsRetry { return L10n.text("health.healthfeatureaccess.disconnect.and.deletion.incomplete.e41b0b") }
    if isConnectingHealth && !healthConnected { return L10n.text("health.healthfeatureaccess.processing.health.read.request.8354a0") }
    guard healthConnected else { return L10n.text("health.healthfeatureaccess.not.connected.f2f3e9") }
    if (health as? HealthDataService)?.isSyncing == true { return L10n.text("health.healthfeatureaccess.syncing.health.data.5392b0") }
    if isConnectingHealth { return L10n.text("health.healthfeatureaccess.processing.health.read.request.8354a0") }
    guard let health else { return L10n.text("health.healthfeatureaccess.health.reads.unavailable.e967eb") }
    guard let snapshot = try? health.localSnapshot(
      window: .init(start: .distantPast, end: .distantFuture))
    else { return L10n.text("health.healthfeatureaccess.health.read.status.unavailable.2843be") }
    if snapshot.statuses.contains(where: { $0.state == .failed }) {
      return L10n.text("health.healthfeatureaccess.some.health.data.did.not.sync.6df122")
    }
    if !snapshot.samples.isEmpty { return L10n.text("health.healthfeatureaccess.imported.health.data.on.this.device.1ce009") }
    if snapshot.statuses.contains(where: { $0.state == .noSamples }) {
      return L10n.text("health.healthfeatureaccess.no.health.samples.read.yet.e36db5")
    }
    return L10n.text("health.healthfeatureaccess.connection.request.completed.waiting.to.sync.976913")
  }
  var healthConnectionDetail: String? {
    guard healthConnected else { return nil }
    let permissionNote = L10n.text("health.healthfeatureaccess.read.access.is.managed.in.health.d632e0")
    guard let health,
      let snapshot = try? health.localSnapshot(
        window: .init(start: .distantPast, end: .distantFuture))
    else { return L10n.text("health.healthfeatureaccess.connection.request.completed.health.read.status.b2457f", String(permissionNote)) }
    let syncNote: String
    if isConnectingHealth || (health as? HealthDataService)?.isSyncing == true {
      syncNote = L10n.text("health.healthfeatureaccess.syncing.b852b8")
    } else if snapshot.statuses.contains(where: { $0.state == .failed }) {
      syncNote = L10n.text("health.healthfeatureaccess.the.latest.sync.partly.failed.40658f")
    } else if !snapshot.statuses.isEmpty && snapshot.statuses.allSatisfy({
      $0.state == .noSamples || $0.state == .samplesAvailable
    }) {
      syncNote = L10n.text("health.healthfeatureaccess.the.latest.sync.completed.d74893")
    } else {
      syncNote = L10n.text("health.healthfeatureaccess.waiting.for.sync.to.complete.b9da6b")
    }
    let sampleNote = snapshot.samples.isEmpty
      ? L10n.text("health.healthfeatureaccess.no.imported.samples.are.on.this.6c714c")
      : L10n.text("health.healthfeatureaccess.imported.samples.are.on.this.device.8f3704")
    return L10n.text("health.healthfeatureaccess.connection.request.completed.287fd4", String(syncNote), String(sampleNote), String(permissionNote))
  }
  var aiEnabled: Bool {
    !aiRevocationNeedsRetry && !reports.serverRevocationPending
      && reports.isConfigured && consent?.record(for: .aiReports)?.isGranted == true
      && consent?.record(for: .aiReports)?.version == reports.consentVersion
  }

  func clearError() { errorMessage = nil }

  func connectHealth() async {
    guard !isBusy else { return }
    guard let health else {
      errorMessage = "health.healthfeatureaccess.health.reads.are.unavailable.existing.records.a843bb"
      return
    }
    isBusy = true
    isConnectingHealth = true
    errorMessage = nil
    statusMessage = nil
    defer {
      isBusy = false
      isConnectingHealth = false
    }
    do {
      try await health.requestReadAuthorization()
      healthDeletionNeedsRetry = false
      statusMessage = "health.healthfeatureaccess.connection.request.completed.readable.data.depends.21bf11"
    } catch {
      errorMessage = healthConnected
        ? "health.healthfeatureaccess.connection.request.completed.but.health.sync.8f3dcf"
        : "health.healthfeatureaccess.the.health.connection.request.could.not.1b4179"
    }
  }

  func disconnectHealth() async {
    #if DEBUG
      HealthUITestTrace.record(
        "disconnect.begin", flags: [("busy", isBusy), ("serviceAvailable", health != nil)])
      defer {
        HealthUITestTrace.record(
          "disconnect.end",
          flags: [
            ("busy", isBusy), ("statusSet", statusMessage != nil),
            ("errorSet", errorMessage != nil), ("retry", healthDeletionNeedsRetry),
          ])
      }
    #endif
    guard !isBusy else { return }
    guard let health else {
      errorMessage = "health.healthfeatureaccess.the.health.data.service.is.unavailable.4b6a8e"
      healthDeletionNeedsRetry = true
      return
    }
    isBusy = true
    errorMessage = nil
    statusMessage = nil
    defer { isBusy = false }
    do {
      try await health.disconnectAndDelete()
      healthDeletionNeedsRetry = false
      statusMessage = "health.healthfeatureaccess.disconnected.and.deleted.imported.health.data.d1af18"
      #if DEBUG
        HealthUITestTrace.record("disconnect.success")
      #endif
    } catch {
      healthDeletionNeedsRetry = true
      errorMessage = "health.healthfeatureaccess.this.sync.has.stopped.but.some.f14728"
      #if DEBUG
        HealthUITestTrace.record("disconnect.failure")
      #endif
    }
  }

  /// Only the explicit consent confirmation calls this; never a toggle's initial value.
  func enableAI(at date: Date = .now) async {
    guard !isBusy else { return }
    guard reports.isConfigured, let consent else {
      errorMessage = nil
      showsConfigurationMessage = true
      return
    }
    isBusy = true
    errorMessage = nil
    statusMessage = nil
    defer { isBusy = false }
    do {
      try consent.grant(.aiReports, version: reports.consentVersion, at: date)
      try await reports.activateConsent()
      aiRevocationNeedsRetry = false
      statusMessage = "health.healthfeatureaccess.ai.reports.enabled.you.can.turn.d55401"
    } catch {
      reports.cancelPendingRequests()
      var rollbackFailed = false
      do { try consent.revoke(.aiReports, at: date) } catch { rollbackFailed = true }
      do { try await reports.revokeServerConsent() } catch { rollbackFailed = true }
      aiRevocationNeedsRetry = rollbackFailed || reports.serverRevocationPending
      errorMessage =
        aiRevocationNeedsRetry
        ? "health.healthfeatureaccess.ai.activation.is.incomplete.and.sending.a073b9"
        : "health.healthfeatureaccess.ai.reports.could.not.be.enabled.d68d60"
    }
  }

  func revokeAI(at date: Date = .now) async {
    guard !isBusy else { return }
    isBusy = true
    errorMessage = nil
    statusMessage = nil
    reports.cancelPendingRequests()
    defer { isBusy = false }
    var failed = false
    do { try await reports.closeAI(at: date, consent: consent) } catch { failed = true }
    aiRevocationNeedsRetry = failed || reports.serverRevocationPending
    if aiRevocationNeedsRetry {
      errorMessage = "health.healthfeatureaccess.future.sending.has.stopped.local.saving.fc6c5d"
    } else {
      statusMessage = "health.healthfeatureaccess.ai.reports.turned.off.health.connection.7f10e4"
    }
  }

  func resumePendingRevocation() async {
    let retryingLocalAndServer = aiRevocationNeedsRetry
    do {
      if retryingLocalAndServer {
        // An earlier failure may include the local consent write. Re-run the complete
        // close operation before clearing that flag, even when the server marker is gone.
        try await reports.closeAI(at: .now, consent: consent)
      } else {
        try await reports.resumePendingRevocation()
      }
      aiRevocationNeedsRetry = reports.serverRevocationPending
      if retryingLocalAndServer && !aiRevocationNeedsRetry { errorMessage = nil }
    } catch {
      aiRevocationNeedsRetry = true
      errorMessage = "health.healthfeatureaccess.ai.withdrawal.is.incomplete.and.future.85c993"
    }
  }

  func deleteReports() {
    errorMessage = nil
    statusMessage = nil
    reports.cancelPendingRequests()
    do {
      try reports.deleteAllReports()
      statusMessage = "health.healthfeatureaccess.ai.reports.on.this.device.deleted.d1dfdc"
    } catch { errorMessage = "health.healthfeatureaccess.report.deletion.is.incomplete.try.again.b6a183" }
  }
}
