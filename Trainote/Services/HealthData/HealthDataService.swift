import Foundation
import Observation

@MainActor
@Observable
final class HealthDataService: HealthDataProviding {
  private let client: any HealthQueryClient
  private let cache: HealthCacheStore
  private let consent: LocalConsentStore
  private let clock: () -> Date
  private let preferences: () throws -> AnalysisPreferencesValue
  private var epoch = UUID()
  private var syncTasks: [HealthDataType: Task<Void, Error>] = [:]
  private var pendingTypes = Set<HealthDataType>()
  private var invalidators: [any HealthDerivedDataInvalidating] = []
  private(set) var lastFailure: AnalysisFailure?

  init(
    client: any HealthQueryClient, cache: HealthCacheStore, consent: LocalConsentStore,
    clock: @escaping () -> Date = { .now },
    preferences: @escaping () throws -> AnalysisPreferencesValue = { .init() }
  ) {
    self.client = client
    self.cache = cache
    self.consent = consent
    self.clock = clock
    self.preferences = preferences
    consent.onRevocation(.healthData) { [weak self] in self?.stop() }
  }
  func addDerivedDataInvalidator(_ invalidator: any HealthDerivedDataInvalidating) {
    invalidators.append(invalidator)
  }
  func requestReadAuthorization() async throws {
    let requestEpoch = epoch
    try await client.requestAuthorization()
    guard epoch == requestEpoch else { throw AnalysisFailure.cancelled }
    try consent.grant(.healthData, version: LocalConsentStore.healthConsentVersion, at: clock())
    try await startObserving()
    try await refresh()
  }
  func startObserving() async throws {
    _ = try healthLease()
    do {
      try await client.observe { [weak self] type, completion in
        Task { @MainActor in
          defer { completion() }
          guard let self else { return }
          do { try await self.refresh(type) } catch { self.lastFailure = .readFailed }
        }
      }
    } catch {
      // Foreground refresh still works if background delivery is unavailable.
      lastFailure = .unavailable
    }
  }
  func refresh() async throws {
    _ = try healthLease()
    var failed = false
    for type in HealthDataType.allCases {
      do { try await refresh(type) } catch { failed = true }
    }
    if failed {
      lastFailure = .readFailed
      throw AnalysisFailure.readFailed
    }
    lastFailure = nil
  }
  private func refresh(_ type: HealthDataType) async throws {
    let lease = try healthLease()
    if let current = syncTasks[type] {
      pendingTypes.insert(type)
      try await current.value
      return
    }
    let currentEpoch = epoch
    let task = Task { @MainActor in
      defer { syncTasks[type] = nil }
      repeat {
        pendingTypes.remove(type)
        do {
          let batch = try await client.changes(
            type: type, anchor: cache.state.anchors[type.rawValue],
            since: cache.state.syncStart)
          try Task.checkCancellation()
          try consent.validate(lease)
          guard epoch == currentEpoch else { throw AnalysisFailure.cancelled }
          try cache.commit(batch)
        } catch {
          if epoch == currentEpoch { try? cache.markFailure(type, at: clock()) }
          throw error
        }
      } while pendingTypes.contains(type)
    }
    syncTasks[type] = task
    try await task.value
  }
  func localSnapshot(window: AnalysisWindow) throws -> HealthDataSnapshot {
    guard consent.record(for: .healthData)?.isGranted == true else {
      return .disconnected(window: window, asOf: clock())
    }
    return cache.snapshot(window: window, at: clock())
  }
  func freshSnapshot(window: AnalysisWindow, timeZone: TimeZone) async throws -> HealthDataSnapshot
  {
    guard window.start < window.end else { throw AnalysisFailure.invalidInput }
    guard consent.record(for: .healthData)?.isGranted == true else {
      return .disconnected(window: window, asOf: clock())
    }
    let lease = try healthLease()
    let preferred = try preferences().preferredHealthSourceIDs
    var samples: [HealthSample] = []
    var statuses: [HealthReadStatus] = []
    var activityFacts: [MetricFact] = []
    for type in HealthDataType.allCases {
      do {
        let current = try await client.samples(type: type, window: window)
        try consent.validate(lease)
        if type == .steps || type == .activeEnergy {
          var facts = try await client.activityFacts(
            type: type, window: window, timeZone: timeZone,
            preferredSources: preferred)
          try consent.validate(lease)
          for index in facts.indices {
            let sources = Set(facts[index].sources.map(\.identifier))
            facts[index].dependencies = current.filter {
              sources.contains($0.source.bundleIdentifier) && $0.start < facts[index].window.end
                && $0.end >= facts[index].window.start
            }.map { .init(kind: .healthSample, id: $0.id.uuidString, healthType: type) }
          }
          activityFacts += facts.filter { !$0.dependencies.isEmpty }
        }
        samples += current
        statuses.append(
          .init(
            type: type, state: current.isEmpty ? .noSamples : .samplesAvailable, queriedAt: clock())
        )
      } catch {
        try consent.validate(lease)
        statuses.append(.init(type: type, state: .failed, queriedAt: clock(), failure: .readFailed))
      }
    }
    try consent.validate(lease)
    return .init(
      window: window, fetchedAt: clock(), isFresh: true,
      samples: samples.sorted { $0.id.uuidString < $1.id.uuidString },
      statuses: statuses, activityFacts: activityFacts)
  }
  func disconnectAndDelete() async throws {
    var failure: Error?
    do { try consent.revoke(.healthData, at: clock()) } catch { failure = error }
    stop()
    do { try cache.clear(syncStart: clock().addingTimeInterval(-90 * 86_400)) } catch {
      failure = failure ?? error
    }
    for invalidator in invalidators {
      do { try invalidator.deleteHealthDependentData() } catch { failure = failure ?? error }
    }
    if let failure { throw failure }
  }
  private func healthLease() throws -> ConsentLease {
    guard client.isAvailable else { throw AnalysisFailure.unavailable }
    return try consent.lease(for: .healthData, version: LocalConsentStore.healthConsentVersion)
  }
  private func stop() {
    epoch = UUID()
    client.stopObserving()
    syncTasks.values.forEach { $0.cancel() }
    pendingTypes.removeAll()
  }
}
