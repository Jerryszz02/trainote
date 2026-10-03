import XCTest

@testable import Trainote

@MainActor
final class FakeHealthQueryClient: HealthQueryClient {
  var isAvailable = true
  var requested = false
  var stopped = false
  var samplesByType: [HealthDataType: [HealthSample]] = [:]
  var batches: [HealthDataType: HealthAnchorBatch] = [:]
  var failedTypes = Set<HealthDataType>()
  var activity: [HealthDataType: [MetricFact]] = [:]
  var receivedAnchors: [Data?] = []
  var onObserve: ((HealthDataType, @escaping () -> Void) -> Void)?
  var onChangeRequest: (() -> Void)?
  var suspendedType: HealthDataType?
  var suspended: CheckedContinuation<Void, Never>?
  var onSamples: (() throws -> Void)?

  func requestAuthorization() async throws { requested = true }
  func changes(type: HealthDataType, anchor: Data?, since: Date) async throws -> HealthAnchorBatch {
    receivedAnchors.append(anchor)
    onChangeRequest?()
    if suspendedType == type {
      await withCheckedContinuation { suspended = $0 }
    }
    if failedTypes.contains(type) { throw AnalysisFailure.readFailed }
    return batches[type]
      ?? .init(
        type: type, added: [], deletedIDs: [],
        newAnchor: Data(type.rawValue.utf8), queriedAt: AnalysisFixtures.asOf)
  }
  func samples(type: HealthDataType, window: AnalysisWindow) async throws -> [HealthSample] {
    try onSamples?()
    if failedTypes.contains(type) { throw AnalysisFailure.readFailed }
    return samplesByType[type] ?? []
  }
  func activityFacts(
    type: HealthDataType, window: AnalysisWindow, timeZone: TimeZone,
    preferredSources: [String]
  ) async throws -> [MetricFact] { activity[type] ?? [] }
  func observe(_ onChange: @escaping (HealthDataType, @escaping () -> Void) -> Void) async throws {
    onObserve = onChange
  }
  func stopObserving() {
    stopped = true
    onObserve = nil
  }
}

@MainActor
final class HealthSyncTests: XCTestCase {
  private var directory: URL!
  override func setUp() {
    super.setUp()
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }
  override func tearDown() {
    try? FileManager.default.removeItem(at: directory)
    super.tearDown()
  }
  func testCacheCommitIsAtomicIdempotentAndAppliesDeletionBeforeAdvancingAnchor() throws {
    let url = directory.appendingPathComponent("cache.json")
    var failWrites = false
    let cache = try HealthCacheStore(url: url, syncStart: AnalysisFixtures.window.start) {
      data, url in
      if failWrites { throw AnalysisFailure.storageFailed }
      try LocalHealthStorage.write(data, to: url)
    }
    let sample = AnalysisFixtures.health(.complete).samples[0]
    let first = HealthAnchorBatch(
      type: .bodyMass, added: [sample, sample], deletedIDs: [],
      newAnchor: Data([1]), queriedAt: AnalysisFixtures.asOf)
    try cache.commit(first)
    try cache.commit(first)
    XCTAssertEqual(cache.state.samples.count, 1)
    var replacement = sample
    replacement.value = 71
    let second = HealthAnchorBatch(
      type: .bodyMass, added: [replacement], deletedIDs: [],
      newAnchor: Data([2]), queriedAt: AnalysisFixtures.asOf)
    failWrites = true
    XCTAssertThrowsError(try cache.commit(second))
    XCTAssertEqual(cache.state.anchors["bodyMass"], Data([1]))
    XCTAssertEqual(cache.state.samples[sample.id.uuidString]?.value, 70)
    let reopened = try HealthCacheStore(url: url, syncStart: AnalysisFixtures.asOf)
    XCTAssertEqual(reopened.state, cache.state)
    failWrites = false
    try cache.commit(
      .init(
        type: .bodyMass, added: [], deletedIDs: [sample.id, sample.id],
        newAnchor: Data([3]), queriedAt: AnalysisFixtures.asOf))
    XCTAssertTrue(cache.state.samples.isEmpty)
    XCTAssertEqual(cache.state.anchors["bodyMass"], Data([3]))
    XCTAssertTrue(
      try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    XCTAssertTrue(
      try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    )
  }
  func testAuthorizationCompletionAndEmptySamplesAreNotReadPermission() async throws {
    let client = FakeHealthQueryClient()
    let cache = try HealthCacheStore(
      url: directory.appendingPathComponent("cache.json"), syncStart: AnalysisFixtures.window.start)
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    let service = HealthDataService(
      client: client, cache: cache, consent: consent, clock: { AnalysisFixtures.asOf })
    XCTAssertEqual(
      try service.localSnapshot(window: AnalysisFixtures.window).statuses.first?.state,
      .disconnected)
    try await service.requestReadAuthorization()
    XCTAssertTrue(client.requested)
    XCTAssertTrue(consent.record(for: .healthData)?.isGranted == true)
    XCTAssertNil(consent.record(for: .aiReports))
    let empty = try await service.freshSnapshot(window: AnalysisFixtures.window)
    XCTAssertTrue(empty.statuses.allSatisfy { $0.state == .noSamples })
    client.failedTypes = [.heartRateVariabilitySDNN]
    client.samplesByType[.bodyMass] = [AnalysisFixtures.health(.complete).samples[0]]
    let partial = try await service.freshSnapshot(window: AnalysisFixtures.window)
    XCTAssertEqual(partial.statuses.first { $0.type == .heartRateVariabilitySDNN }?.state, .failed)
    XCTAssertEqual(partial.statuses.first { $0.type == .bodyMass }?.state, .samplesAvailable)
  }
  func testObserverAcknowledgesAfterCommitAndForegroundRetriesFailure() async throws {
    let client = FakeHealthQueryClient()
    let cache = try HealthCacheStore(
      url: directory.appendingPathComponent("cache.json"), syncStart: AnalysisFixtures.window.start)
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    try consent.grant(
      .healthData, version: LocalConsentStore.healthConsentVersion, at: AnalysisFixtures.asOf)
    let service = HealthDataService(client: client, cache: cache, consent: consent)
    try await service.startObserving()
    let sample = AnalysisFixtures.health(.complete).samples[0]
    client.batches[.bodyMass] = .init(
      type: .bodyMass, added: [sample], deletedIDs: [],
      newAnchor: Data([9]), queriedAt: AnalysisFixtures.asOf)
    let completion = expectation(description: "Observer acknowledges committed cache")
    client.onObserve?(
      .bodyMass,
      {
        XCTAssertEqual(cache.state.anchors["bodyMass"], Data([9]))
        XCTAssertEqual(cache.state.samples.count, 1)
        completion.fulfill()
      })
    await fulfillment(of: [completion], timeout: 2)
    client.failedTypes = [.sleep]
    do {
      try await service.refresh()
      XCTFail("Expected failed sleep query")
    } catch {}
    XCTAssertNil(cache.state.anchors["sleep"])
    client.failedTypes = []
    try await service.refresh()
    XCTAssertNotNil(cache.state.anchors["sleep"])
    XCTAssertNil(service.lastFailure)
  }
  func testDisconnectPreventsInFlightQueryFromRepopulatingDeletedCache() async throws {
    let client = FakeHealthQueryClient()
    client.suspendedType = .bodyMass
    let cache = try HealthCacheStore(
      url: directory.appendingPathComponent("cache.json"), syncStart: AnalysisFixtures.window.start)
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    try consent.grant(
      .healthData, version: LocalConsentStore.healthConsentVersion, at: AnalysisFixtures.asOf)
    let service = HealthDataService(client: client, cache: cache, consent: consent)
    let started = expectation(description: "Query suspended")
    client.onChangeRequest = { started.fulfill() }
    let task = Task { try await service.refresh() }
    await fulfillment(of: [started], timeout: 2)
    client.onChangeRequest = nil
    try await service.disconnectAndDelete()
    client.suspended?.resume()
    do {
      try await task.value
      XCTFail("Expected cancelled refresh")
    } catch {}
    XCTAssertTrue(cache.state.samples.isEmpty)
    XCTAssertTrue(cache.state.anchors.isEmpty)
    XCTAssertTrue(client.stopped)
    XCTAssertFalse(consent.record(for: .healthData)!.isGranted)
  }
}
