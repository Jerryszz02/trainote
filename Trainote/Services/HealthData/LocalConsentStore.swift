import Foundation
import Observation

@MainActor
@Observable
final class LocalConsentStore: ConsentManaging {
  static let healthConsentVersion = "health-read-v1"
  static let aiConsentVersion = "ai-report-v1"
  private struct State: Codable {
    var schemaVersion = 1
    var records: [String: LocalConsentRecord] = [:]
  }
  private let url: URL
  private let writer: HealthCacheStore.Writer
  private var state: State
  private var generations: [ConsentScope: UUID] = [:]
  private var revocationHandlers: [UUID: (ConsentScope, () -> Void)] = [:]

  init(url: URL, writer: @escaping HealthCacheStore.Writer = LocalHealthStorage.write) throws {
    self.url = url
    self.writer = writer
    try LocalHealthStorage.prepare(url.deletingLastPathComponent())
    if FileManager.default.fileExists(atPath: url.path) {
      state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
      guard state.schemaVersion == 1 else { throw AnalysisFailure.unsupportedVersion }
    } else {
      state = .init()
    }
    for scope in ConsentScope.allCases { generations[scope] = UUID() }
  }
  func record(for scope: ConsentScope) -> LocalConsentRecord? { state.records[scope.rawValue] }
  func grant(_ scope: ConsentScope, version: String, at: Date) throws {
    guard !version.isEmpty, version.count <= 128 else { throw AnalysisFailure.invalidInput }
    var next = state
    next.records[scope.rawValue] = .init(
      scope: scope, version: version, grantedAt: at, revokedAt: nil)
    try writer(JSONEncoder().encode(next), url)
    state = next
    generations[scope] = UUID()
  }
  func revoke(_ scope: ConsentScope, at: Date) throws {
    let old = record(for: scope)
    state.records[scope.rawValue] = .init(
      scope: scope, version: old?.version ?? "",
      grantedAt: old?.grantedAt, revokedAt: at)
    generations[scope] = UUID()
    // Fail closed in memory even if persistence fails; surface the failure so removal can be retried.
    for (registered, handler) in Array(revocationHandlers.values) where registered == scope {
      handler()
    }
    try writer(JSONEncoder().encode(state), url)
  }
  func lease(for scope: ConsentScope, version: String) throws -> ConsentLease {
    guard let record = record(for: scope), record.isGranted, record.version == version else {
      throw AnalysisFailure.consentRequired
    }
    return .init(scope: scope, version: version, generation: generations[scope]!)
  }
  func validate(_ lease: ConsentLease) throws {
    guard let current = record(for: lease.scope), current.isGranted,
      current.version == lease.version,
      generations[lease.scope] == lease.generation
    else { throw AnalysisFailure.consentChanged }
  }
  @discardableResult
  func onRevocation(_ scope: ConsentScope, _ handler: @escaping () -> Void) -> UUID {
    let id = UUID()
    revocationHandlers[id] = (scope, handler)
    return id
  }
  func removeRevocationHandler(_ id: UUID) { revocationHandlers.removeValue(forKey: id) }
}
