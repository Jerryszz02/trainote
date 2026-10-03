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
  private(set) var errorMessage: String?
  private(set) var statusMessage: String?
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
  var aiEnabled: Bool {
    !aiRevocationNeedsRetry && !reports.serverRevocationPending
      && reports.isConfigured && consent?.record(for: .aiReports)?.isGranted == true
      && consent?.record(for: .aiReports)?.version == reports.consentVersion
  }

  func clearError() { errorMessage = nil }

  func connectHealth() async {
    guard !isBusy else { return }
    guard let health else {
      errorMessage = "健康读取暂不可用。原有记录可继续使用，请重新启动后重试。"
      return
    }
    isBusy = true
    errorMessage = nil
    statusMessage = nil
    defer { isBusy = false }
    do {
      try await health.requestReadAuthorization()
      healthDeletionNeedsRetry = false
      statusMessage = "已完成连接请求。实际可读内容取决于你在 Apple 健康中选择的数据；没有样本不代表拒绝权限。"
    } catch {
      errorMessage = "未能完成健康读取，请重试。你仍可仅使用本地记录，也可在设置中断开并删除导入数据。"
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
      errorMessage = "健康数据服务不可用，尚未完成删除。请重新启动后重试。"
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
      statusMessage = "已断开并删除健康导入数据及相关报告。手动记录已保留。"
      #if DEBUG
        HealthUITestTrace.record("disconnect.success")
      #endif
    } catch {
      healthDeletionNeedsRetry = true
      errorMessage = "已停止本次同步，但部分删除或保存未完成。请重试“断开并删除”，不要把本次操作视为删除成功。"
      #if DEBUG
        HealthUITestTrace.record("disconnect.failure")
      #endif
    }
  }

  /// Only the explicit consent confirmation calls this; never a toggle's initial value.
  func enableAI(at date: Date = .now) async {
    guard !isBusy else { return }
    guard reports.isConfigured, let consent else {
      errorMessage = reports.configurationMessage
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
      statusMessage = "已启用 AI 报告。可随时在设置中关闭。"
    } catch {
      reports.cancelPendingRequests()
      var rollbackFailed = false
      do { try consent.revoke(.aiReports, at: date) } catch { rollbackFailed = true }
      do { try await reports.revokeServerConsent() } catch { rollbackFailed = true }
      aiRevocationNeedsRetry = rollbackFailed || reports.serverRevocationPending
      errorMessage =
        aiRevocationNeedsRetry
        ? "AI 启用未完成，已停止发送。撤回仍需重试，请在设置中完成撤回。"
        : "未能启用 AI 报告。已撤回本次同意，继续使用本地基础报告。"
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
      errorMessage = "已停止后续发送。本机保存或服务器撤回尚未完成，请重试撤回。"
    } else {
      statusMessage = "已关闭 AI 报告。健康连接和本地分析继续保留，历史报告可单独删除。"
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
      errorMessage = "AI 撤回尚未完成，已停止后续发送。请在设置中重试撤回。"
    }
  }

  func deleteReports() {
    errorMessage = nil
    statusMessage = nil
    reports.cancelPendingRequests()
    do {
      try reports.deleteAllReports()
      statusMessage = "已删除本机 AI 报告。"
    } catch { errorMessage = "报告删除未完成，请重试。" }
  }
}
