import Foundation

struct AIReportContent: Codable, Equatable, Identifiable {
  var report: ReportResult
  var input: ReportInput
  var dependsOnHealth: Bool
  var id: String { report.reportID }
  func isExpired(at date: Date) -> Bool { report.validUntil <= date }
}

@MainActor
final class AIReportCache: HealthDerivedDataInvalidating {
  private struct State: Codable { var version = 1; var reports: [String: AIReportContent] = [:] }
  private var state: State
  private let url: URL
  private let writer: HealthCacheStore.Writer
  init(url: URL, allowHealthHistory: Bool, writer: @escaping HealthCacheStore.Writer = LocalHealthStorage.write) throws {
    self.url = url
    self.writer = writer
    try LocalHealthStorage.prepare(url.deletingLastPathComponent())
    if FileManager.default.fileExists(atPath: url.path) {
      let bytes = try Data(contentsOf: url)
      guard bytes.count <= 4 * 1024 * 1024 else { throw AIReportFailure.storage }
      state = try AIReportPolicy.decoder().decode(State.self, from: bytes)
      guard state.version == 1, state.reports.count <= 20 else { throw AIReportFailure.storage }
    } else { state = .init() }
    if !allowHealthHistory { try deleteHealthDependentData() }
  }
  static func key(_ input: ReportInput) throws -> String {
    let projection = try ReportWireInput(input)
    let data = try AIReportPolicy.encoder().encode(projection)
    return AIReportPolicy.digest(data + Data(AIReportPolicy.promptVersion.utf8))
  }
  func current(_ input: ReportInput, now: Date) throws -> AIReportContent? {
    guard let content = state.reports[try Self.key(input)] else { return nil }
    // Revalidate persisted content against fresh facts, not the saved snapshot.
    guard (try? ReportResultValidator.validate(content.report, input: input, now: now)) != nil else { return nil }
    return content
  }
  func save(_ content: AIReportContent) throws {
    guard !content.report.isLocalFallback else { return }
    var next = state
    next.reports[try Self.key(content.input)] = content
    let sorted = next.reports.sorted { $0.value.report.generatedAt > $1.value.report.generatedAt }.prefix(20)
    next.reports = Dictionary(uniqueKeysWithValues: sorted.map { ($0.key, $0.value) })
    try writer(AIReportPolicy.encoder().encode(next), url)
    state = next
  }
  func history() -> [AIReportContent] {
    state.reports.values.filter {
      // History may be expired; validate at generation time before exposing persisted text.
      (try? ReportResultValidator.validate($0.report, input: $0.input, now: $0.report.generatedAt)) != nil
    }.sorted { $0.report.generatedAt > $1.report.generatedAt }
  }
  func deleteHealthDependentData() throws {
    state.reports = state.reports.filter { !$0.value.dependsOnHealth }
    try writer(AIReportPolicy.encoder().encode(state), url)
  }
  func deleteAll() throws {
    state = .init() // Fail closed in memory, even when disk deletion must be retried.
    try writer(AIReportPolicy.encoder().encode(state), url)
  }
}
