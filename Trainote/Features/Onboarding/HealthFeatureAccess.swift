import Foundation
import Observation

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
  func deleteAllReports() throws
}

/// No provider, transport, credentials or cache exists in this local-only assembly.
@MainActor
final class LocalOnlyReportAccess: AIReportLifecycle {
  let isConfigured = false
  let consentVersion = LocalConsentStore.aiConsentVersion
  let serverRevocationPending = false
  let configurationMessage = "AI 报告尚未开放。完成代理配置、设备认证及 DeepSeek API 数据处理条款核验后，才能单独选择启用。目前可继续使用本地记录。"
  func activateConsent() async throws { throw AnalysisFailure.unavailable }
  func cancelPendingRequests() {}
  func revokeServerConsent() async throws {}
  func deleteAllReports() throws {}
  func deleteHealthDependentData() throws {}
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
    } catch {
      healthDeletionNeedsRetry = true
      errorMessage = "已停止本次同步，但部分删除或保存未完成。请重试“断开并删除”，不要把本次操作视为删除成功。"
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
    var failures = [String]()
    if let consent {
      do { try consent.revoke(.aiReports, at: date) } catch { failures.append("本机撤回保存失败") }
    } else {
      failures.append("本机同意记录不可用")
    }
    // A local storage failure must not prevent the server revocation attempt.
    do { try await reports.revokeServerConsent() } catch { failures.append("服务器撤回待重试") }
    aiRevocationNeedsRetry = !failures.isEmpty || reports.serverRevocationPending
    if aiRevocationNeedsRetry {
      errorMessage = "已停止后续发送。\(failures.joined(separator: "；"))。请重试撤回。"
    } else {
      statusMessage = "已关闭 AI 报告。健康连接和本地分析继续保留，历史报告可单独删除。"
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
