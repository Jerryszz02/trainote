import Foundation

/// Local reconstructible/imported state, explicitly excluded from system and JSON backups.
enum LocalHealthStorage {
  static var directory: URL {
    URL.applicationSupportDirectory.appendingPathComponent("HealthLocal", isDirectory: true)
  }
  static func prepare(_ directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var directory = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try directory.setResourceValues(values)
  }
  static func write(_ data: Data, to url: URL) throws {
    try prepare(url.deletingLastPathComponent())
    try data.write(
      to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    var url = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }
}

struct HealthAnchorBatch: Equatable {
  var type: HealthDataType
  var added: [HealthSample]
  var deletedIDs: [UUID]
  var newAnchor: Data
  var queriedAt: Date
}
struct HealthCacheState: Codable, Equatable {
  var schemaVersion = 1
  /// The anchor predicate is fixed for this cache lifetime, including app restarts.
  var syncStart: Date
  var samples: [String: HealthSample] = [:]
  var anchors: [String: Data] = [:]
  var statuses: [String: HealthReadStatus] = [:]
}

@MainActor
final class HealthCacheStore {
  typealias Writer = (Data, URL) throws -> Void
  private let url: URL
  private let writer: Writer
  private(set) var state: HealthCacheState

  init(url: URL, syncStart: Date, writer: @escaping Writer = LocalHealthStorage.write) throws {
    self.url = url
    self.writer = writer
    try LocalHealthStorage.prepare(url.deletingLastPathComponent())
    if FileManager.default.fileExists(atPath: url.path) {
      state = try JSONDecoder().decode(HealthCacheState.self, from: Data(contentsOf: url))
      guard state.schemaVersion == 1 else { throw AnalysisFailure.unsupportedVersion }
    } else {
      state = .init(syncStart: syncStart)
    }
  }
  func commit(_ batch: HealthAnchorBatch) throws {
    guard
      batch.added.allSatisfy({
        $0.type == batch.type && $0.start <= $0.end
          && $0.value.map(\.isFinite) != false
      })
    else { throw AnalysisFailure.invalidInput }
    var next = state
    for sample in batch.added { next.samples[sample.id.uuidString] = sample }
    for id in batch.deletedIDs { next.samples.removeValue(forKey: id.uuidString) }
    let cutoff = batch.queriedAt.addingTimeInterval(-90 * 86_400)
    next.samples = next.samples.filter { $0.value.end >= cutoff }
    next.anchors[batch.type.rawValue] = batch.newAnchor
    next.statuses[batch.type.rawValue] = .init(
      type: batch.type,
      state: next.samples.values.contains { $0.type == batch.type }
        ? .samplesAvailable : .noSamples,
      queriedAt: batch.queriedAt)
    // One atomic file transaction holds both samples and anchors. In-memory state advances only after success.
    try writer(JSONEncoder().encode(next), url)
    state = next
  }
  func markFailure(_ type: HealthDataType, at date: Date) throws {
    var next = state
    next.statuses[type.rawValue] = .init(
      type: type, state: .failed, queriedAt: date, failure: .readFailed)
    try writer(JSONEncoder().encode(next), url)
    state = next
  }
  func snapshot(window: AnalysisWindow, at date: Date) -> HealthDataSnapshot {
    .init(
      window: window, fetchedAt: date, isFresh: false,
      samples: state.samples.values.filter { $0.start < window.end && $0.end >= window.start }
        .sorted { $0.id.uuidString < $1.id.uuidString },
      statuses: HealthDataType.allCases.map {
        state.statuses[$0.rawValue] ?? .init(type: $0, state: .unknown, queriedAt: date)
      })
  }
  func clear(syncStart: Date) throws {
    let next = HealthCacheState(syncStart: syncStart)
    try writer(JSONEncoder().encode(next), url)
    state = next
  }
}
