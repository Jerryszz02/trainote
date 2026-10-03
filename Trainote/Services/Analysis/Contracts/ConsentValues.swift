import Foundation

enum ConsentScope: String, Codable, CaseIterable, Sendable { case healthData, aiReports }
struct LocalConsentRecord: Codable, Equatable, Sendable {
  var scope: ConsentScope
  var version: String
  var grantedAt: Date?
  var revokedAt: Date?
  var isGranted: Bool { grantedAt != nil && revokedAt == nil }
}
struct ConsentLease: Codable, Equatable, Sendable {
  var scope: ConsentScope
  var version: String
  var generation: UUID
}
@MainActor
protocol ConsentManaging {
  func record(for scope: ConsentScope) -> LocalConsentRecord?
  func grant(_ scope: ConsentScope, version: String, at: Date) throws
  func revoke(_ scope: ConsentScope, at: Date) throws
  func lease(for scope: ConsentScope, version: String) throws -> ConsentLease
  func validate(_ lease: ConsentLease) throws
}
/// Consumers delete derived snapshots/reports on health disconnection; E supplies its cache.
@MainActor
protocol HealthDerivedDataInvalidating {
  func deleteHealthDependentData() throws
}
