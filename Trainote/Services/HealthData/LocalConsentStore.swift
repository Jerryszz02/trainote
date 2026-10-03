import Foundation
import Observation

@MainActor
@Observable
final class LocalConsentStore: ConsentManaging {
  static let healthConsentVersion = "health-read-v1"
  static let aiConsentVersion = "ai-report-v1"
  private struct State: Codable {
    var schemaVersion = 2
    var records: [String: LocalConsentRecord] = [:]
    /// Written atomically with an explicit grant, never by remote-consent cleanup.
    var acknowledgedRevocations: [String: UUID]? = nil
  }
  private struct RevocationIntent: Codable {
    var schemaVersion = 1
    var scope: ConsentScope
    var id: UUID
    var revokedAt: Date
  }
  private let url: URL
  private let writer: HealthCacheStore.Writer
  private let revocationWriter: HealthCacheStore.Writer
  private var state: State
  private var revocations: [ConsentScope: RevocationIntent] = [:]
  private var generations: [ConsentScope: UUID] = [:]
  private var revocationHandlers: [UUID: (ConsentScope, () -> Void)] = [:]

  convenience init(
    url: URL, writer: @escaping HealthCacheStore.Writer = LocalHealthStorage.write
  ) throws {
    try self.init(url: url, writer: writer, revocationWriter: LocalHealthStorage.write)
  }

  // Both injected writers are required so old trailing-closure calls still target `writer`.
  init(
    url: URL, writer: @escaping HealthCacheStore.Writer,
    revocationWriter: @escaping HealthCacheStore.Writer
  ) throws {
    self.url = url
    self.writer = writer
    self.revocationWriter = revocationWriter
    state = .init()
    try LocalHealthStorage.prepare(url.deletingLastPathComponent())
    // Read independent withdrawal records first. Corrupt/unreadable files must never look absent.
    for scope in ConsentScope.allCases {
      if let data = try Self.readIfPresent(revocationURL(scope)) {
        let intent = try JSONDecoder().decode(RevocationIntent.self, from: data)
        guard intent.schemaVersion == 1, intent.scope == scope,
          intent.revokedAt.timeIntervalSinceReferenceDate.isFinite
        else { throw AnalysisFailure.invalidInput }
        revocations[scope] = intent
      }
    }
    if let data = try Self.readIfPresent(url) {
      state = try JSONDecoder().decode(State.self, from: data)
      guard (1...2).contains(state.schemaVersion) else { throw AnalysisFailure.unsupportedVersion }
      state.schemaVersion = 2
    }
    for scope in ConsentScope.allCases {
      if let intent = revocations[scope] {
        if state.acknowledgedRevocations?[scope.rawValue] != intent.id {
          let date = max(state.records[scope.rawValue]?.revokedAt ?? intent.revokedAt, intent.revokedAt)
          markRevoked(scope, at: date)
        }
      } else if state.acknowledgedRevocations?[scope.rawValue] != nil {
        // A confirmed post-withdrawal grant must still have its matching journal record.
        throw AnalysisFailure.storageFailed
      }
      generations[scope] = UUID()
    }
  }
  func record(for scope: ConsentScope) -> LocalConsentRecord? { state.records[scope.rawValue] }
  func grant(_ scope: ConsentScope, version: String, at: Date) throws {
    guard !version.isEmpty, version.count <= 128 else { throw AnalysisFailure.invalidInput }
    if let intent = revocations[scope], state.acknowledgedRevocations?[scope.rawValue] != intent.id {
      // A previous intent write may have failed while the revoked main state succeeded. Re-save
      // this exact intent before acknowledging it, then confirm the old grant is durably revoked.
      try revocationWriter(JSONEncoder().encode(intent), revocationURL(scope))
      try writer(JSONEncoder().encode(state), url)
    }
    var next = state
    next.records[scope.rawValue] = .init(
      scope: scope, version: version, grantedAt: at, revokedAt: nil)
    var acknowledgements = next.acknowledgedRevocations ?? [:]
    acknowledgements[scope.rawValue] = revocations[scope]?.id
    next.acknowledgedRevocations = acknowledgements
    do {
      // Grant and journal acknowledgement are one atomic write. No marker is deleted, so there
      // is no successful in-memory grant followed by a failed cleanup and denial after restart.
      try writer(JSONEncoder().encode(next), url)
    } catch {
      let grantError = error
      // A writer can throw after replacing the file (e.g. while applying backup protection).
      // Replace the journal token to invalidate any possibly written grant receipt. The original
      // error is always surfaced; if both storage paths fail, durability cannot be guaranteed.
      try? revoke(scope, at: at)
      throw grantError
    }
    state = next
    generations[scope] = UUID()
  }
  func revoke(_ scope: ConsentScope, at: Date) throws {
    let intent = RevocationIntent(scope: scope, id: UUID(), revokedAt: at)
    revocations[scope] = intent
    markRevoked(scope, at: at)
    generations[scope] = UUID()
    // Cancel immediately, before any disk access. Old leases stay invalid even on a failed write.
    for (registered, handler) in Array(revocationHandlers.values) where registered == scope {
      handler()
    }
    var failure: Error?
    do { try revocationWriter(JSONEncoder().encode(intent), revocationURL(scope)) }
    catch { failure = error }
    // If the journal path fails, still try to persist the revoked original record. Either durable
    // path suffices to block restart; a failed stage is reported and can be explicitly retried.
    do { try writer(JSONEncoder().encode(state), url) }
    catch { if failure == nil { failure = error } }
    if let failure { throw failure }
  }

  private func markRevoked(_ scope: ConsentScope, at: Date) {
    let old = state.records[scope.rawValue]
    state.records[scope.rawValue] = .init(
      scope: scope, version: old?.version ?? "", grantedAt: old?.grantedAt, revokedAt: at)
    state.acknowledgedRevocations?[scope.rawValue] = nil
  }

  private func revocationURL(_ scope: ConsentScope) -> URL {
    url.appendingPathExtension("revocation-\(scope.rawValue).json")
  }

  private static func readIfPresent(_ url: URL) throws -> Data? {
    do { return try Data(contentsOf: url) }
    catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
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
