import Foundation

enum AIReportAssembly {
  /// The default is entirely local. A reviewed deployment configuration is required to create network transport.
  @MainActor static func make(foundation: HealthFoundation,
    trend: any TrendCalculating, recovery: any RecoveryCalculating,
    recommendations: any RecommendationProviding,
    proxy: ReportProxyConfiguration? = nil,
    directory: URL = LocalHealthStorage.directory.appendingPathComponent("AIReports", isDirectory: true)
  ) throws -> AIReportService {
    guard let consent = foundation.consent, let health = foundation.healthData else { throw AIReportFailure.unavailable }
    let cache = try AIReportCache(url: directory.appendingPathComponent("reports.json"),
      allowHealthHistory: consent.record(for: .healthData)?.isGranted == true)
    let builder = ReportSnapshotBuilder(repository: foundation.repository, health: health,
      consent: consent, trend: trend, recovery: recovery, recommendations: recommendations)
    let transport: ProxyReportTransport?
    if let proxy {
      transport = try ProxyReportTransport(configuration: proxy,
        credentials: KeychainReportCredentials(proxyHost: proxy.baseURL.host!),
        attestor: AppleReportDeviceAttestor(), http: ReportProxyHTTP())
    } else { transport = nil }
    return AIReportService(builder: builder, consent: consent, healthData: health, cache: cache, transport: transport)
  }
}
