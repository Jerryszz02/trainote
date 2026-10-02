import CryptoKit
import Foundation

enum AIReportPolicy {
  static let knowledgeVersion = "health-evidence-v1"
  static let promptVersion = "report-selection-v1"
  static let model = "deepseek-flash"
  static let reportLifetime: TimeInterval = 6 * 3600
  static let maximumInputAge: TimeInterval = 24 * 3600
  static let maximumPreparedAge: TimeInterval = 60
  static let requestByteLimit = 128 * 1024
  static let responseByteLimit = 32 * 1024

  static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    // The frozen proxy contract uses integer milliseconds, including real sub-millisecond Date values.
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      let milliseconds = (date.timeIntervalSince1970 * 1000).rounded(.down)
      guard milliseconds.isFinite, (0...9e15).contains(milliseconds) else { throw AIReportFailure.invalidInput }
      try container.encode(Int64(milliseconds))
    }
    return encoder
  }
  static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return decoder
  }
  static func identifier(_ value: String) -> Bool {
    value.range(of: "^[A-Za-z0-9_.:-]{1,128}$", options: .regularExpression) != nil
  }
  static func calculationVersion(_ value: String) -> Bool {
    value.range(of: "^[A-Za-z0-9_.:+-]{1,128}$", options: .regularExpression) != nil
  }
  static func localIdentifier(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 4096 && value.rangeOfCharacter(from: .controlCharacters) == nil
  }
}

enum AIReportFailure: Error, Equatable {
  case unavailable, invalidInput, invalidResponse, stale, cancelled, storage
  case consentRequired, revocationPending, deviceUnavailable, server(Int)
}

/// The fresh dependency closure stays local. Send summary facts and every approved candidate's reasons.
enum ReportFactSelection {
  static func wireWindow(_ fact: MetricFact, asOf: Date) throws -> AnalysisWindow {
    guard fact.window.start <= fact.window.end else { throw AIReportFailure.invalidInput }
    // F labels observed recommendation context with the whole local day (including DST).
    // Project only its elapsed portion; all other future observations remain invalid.
    if fact.window.end > asOf.addingTimeInterval(60) {
      guard fact.metric.hasPrefix("recommendation."),
        fact.sources.contains(where: { $0.kind == .calculation && $0.identifier == "trainote.recommendations" }),
        fact.window.start <= asOf, fact.window.end.timeIntervalSince(fact.window.start) <= 26 * 3600
      else { throw AIReportFailure.invalidInput }
      return .init(start: fact.window.start, end: asOf)
    }
    return fact.window
  }
  static func facts(_ input: ReportInput) -> [MetricFact] {
    let reasons = Set(input.candidates.flatMap(\.reasonFactIDs))
    let rawMetrics = Set(HealthDataType.allCases.map(\.rawValue) + ["sleep.duration"])
    let summaries = input.facts.filter {
      reasons.contains($0.id) || !(rawMetrics.contains($0.metric) && $0.sources.contains { $0.kind == .healthKit })
    }
    if !summaries.isEmpty {
      return summaries.sorted {
        if reasons.contains($0.id) != reasons.contains($1.id) { return reasons.contains($0.id) }
        return $0.id < $1.id
      }
    }
    // A measurement-only report keeps one latest observed fact per metric, never an arbitrary prefix.
    return Dictionary(grouping: input.facts, by: \.metric).values.compactMap { group in
      group.sorted { $0.window.end == $1.window.end ? $0.id < $1.id : $0.window.end > $1.window.end }.first
    }.sorted { $0.id < $1.id }
  }
}

/// A minimal transport projection of A's ReportInput. Never serializes source/sample IDs or user text.
struct ReportWireInput: Encodable {
  struct Fact: Encodable {
    var id: String
    var metric: String
    var value: Double?
    var unit: MetricUnit
    var window: AnalysisWindow
    var quality: [DataQualityFlag]
    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(id, forKey: .id)
      try container.encode(metric, forKey: .metric)
      try container.encode(value, forKey: .value) // explicit null means unknown
      try container.encode(unit, forKey: .unit)
      try container.encode(window, forKey: .window)
      try container.encode(quality, forKey: .quality)
    }
    enum CodingKeys: String, CodingKey { case id, metric, value, unit, window, quality }
  }
  struct Candidate: Encodable {
    var actionID: String
    var action: RecommendationAction
    var muscleIDs: [MuscleID]
    var reasonFactIDs: [String]
  }
  var schemaVersion: Int
  var reportType: ReportType
  var asOf: Date
  var inputFingerprint: String
  var facts: [Fact]
  var candidates: [Candidate]
  var goalDirection: GoalDirection?
  var knowledgeVersion: String
  var calculationVersions: [String]
  var missingData: [String]
  private var localFacts: [String: MetricFact]
  private var localCandidates: [String: RecommendationCandidate]

  static func validateLocal(_ input: ReportInput) throws {
    let ids = Set(input.facts.map(\.id))
    guard input.schemaVersion == 1, input.knowledgeVersion == AIReportPolicy.knowledgeVersion,
      input.inputFingerprint.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
      input.facts.count <= 4096, ids.count == input.facts.count,
      input.candidates.count <= 12,
      Set(input.candidates.map(\.actionID)).count == input.candidates.count,
      (1...8).contains(input.calculationVersions.count),
      input.calculationVersions.allSatisfy(AIReportPolicy.calculationVersion),
      input.missingData.count <= 32, input.missingData.allSatisfy(AIReportPolicy.identifier),
      input.facts.allSatisfy({
        AIReportPolicy.localIdentifier($0.id) && AIReportPolicy.identifier($0.metric)
          && ($0.value == nil || ($0.value!.isFinite && abs($0.value!) <= 1e12))
          && (try? ReportFactSelection.wireWindow($0, asOf: input.asOf)) != nil
          && $0.quality.count <= 12
      }), input.candidates.allSatisfy({
        AIReportPolicy.localIdentifier($0.actionID) && $0.reasonFactIDs.allSatisfy(ids.contains)
          && $0.muscleIDs.count <= 11 && $0.reasonFactIDs.count <= 100
      })
    else { throw AIReportFailure.invalidInput }
  }
  init(_ input: ReportInput) throws {
    try Self.validateLocal(input)
    let selected = ReportFactSelection.facts(input).sorted { $0.id < $1.id }
    guard selected.count <= 100 else { throw AIReportFailure.invalidInput }
    let factIDs = Dictionary(uniqueKeysWithValues: selected.enumerated().map { ($0.element.id, "f\($0.offset)") })
    let candidatesByID = input.candidates.sorted { $0.actionID < $1.actionID }
    localFacts = Dictionary(uniqueKeysWithValues: selected.enumerated().map { ("f\($0.offset)", $0.element) })
    localCandidates = Dictionary(uniqueKeysWithValues: candidatesByID.enumerated().map { ("a\($0.offset)", $0.element) })
    schemaVersion = input.schemaVersion
    reportType = input.reportType
    asOf = input.asOf
    inputFingerprint = input.inputFingerprint
    facts = try selected.map { .init(id: factIDs[$0.id]!, metric: $0.metric, value: $0.value,
      unit: $0.unit, window: try ReportFactSelection.wireWindow($0, asOf: input.asOf), quality: $0.quality) }
    // Candidates are already approved by F. exclusionCodes are constraints, not an eligibility flag.
    candidates = try candidatesByID.enumerated().map { index, candidate in
      let reasons = try candidate.reasonFactIDs.map { id -> String in
        guard let wireID = factIDs[id] else { throw AIReportFailure.invalidInput }
        return wireID
      }
      return .init(actionID: "a\(index)", action: candidate.action, muscleIDs: candidate.muscleIDs, reasonFactIDs: reasons)
    }
    goalDirection = input.goalDirection
    knowledgeVersion = input.knowledgeVersion
    calculationVersions = input.calculationVersions
    missingData = input.missingData
  }
  /// Value-only view of exactly what was sent, for strict response validation before local ID restoration.
  var validationInput: ReportInput {
    .init(reportType: reportType, asOf: asOf, inputFingerprint: inputFingerprint,
      facts: facts.map { .init(id: $0.id, metric: $0.metric, value: $0.value, unit: $0.unit,
        window: $0.window, sources: [], quality: $0.quality) },
      candidates: candidates.map { .init(actionID: $0.actionID, action: $0.action,
        muscleIDs: $0.muscleIDs, reasonFactIDs: $0.reasonFactIDs) }, goalDirection: goalDirection,
      knowledgeVersion: knowledgeVersion, calculationVersions: calculationVersions, missingData: missingData)
  }
  func restore(_ report: ReportResult) throws -> ReportResult {
    var result = report
    result.observations = try report.observations.map { observation in
      guard observation.evidenceIDs.count == 1, let fact = localFacts[observation.evidenceIDs[0]] else {
        throw AIReportFailure.invalidResponse
      }
      return .init(text: ReportText.observation(fact), evidenceIDs: [fact.id])
    }
    result.recommendations = try report.recommendations.map { recommendation in
      guard let candidate = localCandidates[recommendation.actionID] else { throw AIReportFailure.invalidResponse }
      return .init(text: ReportText.action(candidate.action), actionID: candidate.actionID)
    }
    return result
  }
  enum CodingKeys: String, CodingKey {
    case schemaVersion, reportType, asOf, inputFingerprint, facts, candidates, goalDirection,
      knowledgeVersion, calculationVersions, missingData
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(schemaVersion, forKey: .schemaVersion)
    try c.encode(reportType, forKey: .reportType)
    try c.encode(asOf, forKey: .asOf)
    try c.encode(inputFingerprint, forKey: .inputFingerprint)
    try c.encode(facts, forKey: .facts)
    try c.encode(candidates, forKey: .candidates)
    try c.encode(goalDirection, forKey: .goalDirection)
    try c.encode(knowledgeVersion, forKey: .knowledgeVersion)
    try c.encode(calculationVersions, forKey: .calculationVersions)
    try c.encode(missingData, forKey: .missingData)
  }
}

struct ReportRequestEnvelope: Encodable {
  var schemaVersion = 1
  var requestID: String
  var reportType: ReportType
  var inputFingerprint: String
  var consentVersion: String
  var input: ReportWireInput
  @MainActor init(input: ReportInput, requestID: UUID) throws {
    self.requestID = requestID.uuidString.lowercased()
    reportType = input.reportType
    inputFingerprint = input.inputFingerprint
    consentVersion = LocalConsentStore.aiConsentVersion
    self.input = try ReportWireInput(input)
  }
}

enum ReportText {
  static func summary(_ input: ReportInput) -> String {
    ReportFactSelection.facts(input).contains { $0.value != nil }
      ? "根据当前记录，可查看以下事实与候选建议。" : "当前记录不足，补充记录后再看变化。"
  }
  static func observation(_ fact: MetricFact) -> String {
    guard fact.value != nil else { return "暂无可用记录：{{fact:\(fact.id)}}。" }
    return "\(fact.quality.isEmpty ? "记录值：" : "记录仍有缺失或估计："){{fact:\(fact.id)}}。"
  }
  static func action(_ action: RecommendationAction) -> String {
    switch action {
    case .keepPlan: "可保持原训练计划。"
    case .reduceSets: "可按规则候选减少工作组。"
    case .increaseRIR: "可按规则候选增加保留次数。"
    case .swapTrainingDay: "可考虑调换训练日。"
    case .rest: "可考虑休息。"
    case .lightActivity: "可考虑轻活动。"
    case .choosePlan: "先选择训练模板或目标。"
    case .reviewNutrition: "可复核当前营养目标与执行记录。"
    }
  }
  static func display(_ observation: ReportObservation, facts: [MetricFact]) -> String {
    var text = observation.text
    for fact in facts where observation.evidenceIDs.contains(fact.id) {
      let number = fact.value.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "未知"
      let units: [MetricUnit: String] = [.kilograms: "kg", .centimeters: "cm", .kilocalories: "kcal",
        .grams: "g", .seconds: "秒", .milliseconds: "ms", .beatsPerMinute: "次/分", .count: "次",
        .percent: "%", .score: "分", .kilogramsPerWeek: "kg/周", .percentPerWeek: "%/周", .none: ""]
      text = text.replacingOccurrences(of: "{{fact:\(fact.id)}}", with: "\(number)\(fact.value == nil ? "" : units[fact.unit] ?? "")")
    }
    return text
  }
}

struct LocalReportGenerator: ReportGenerating {
  func generate(_ input: ReportInput) async throws -> ReportResult { make(input) }
  func make(_ input: ReportInput) -> ReportResult {
    .init(reportID: "local-" + UUID().uuidString, inputFingerprint: input.inputFingerprint,
      model: "local", promptVersion: AIReportPolicy.promptVersion, summary: ReportText.summary(input),
      observations: ReportFactSelection.facts(input).prefix(3).map { .init(text: ReportText.observation($0), evidenceIDs: [$0.id]) },
      recommendations: input.candidates.prefix(3).map {
        .init(text: ReportText.action($0.action), actionID: $0.actionID)
      }, generatedAt: input.asOf, validUntil: input.asOf.addingTimeInterval(AIReportPolicy.reportLifetime),
      isLocalFallback: true)
  }
}

enum ReportResultValidator {
  static func decode(_ data: Data, input: ReportInput, now: Date) throws -> ReportResult {
    guard data.count <= AIReportPolicy.responseByteLimit,
      let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(raw.keys) == Set(["reportID", "inputFingerprint", "model", "promptVersion", "schemaVersion",
        "summary", "observations", "recommendations", "generatedAt", "validUntil", "isLocalFallback"]),
      let observations = raw["observations"] as? [[String: Any]],
      observations.allSatisfy({ Set($0.keys) == Set(["text", "evidenceIDs"]) }),
      let recommendations = raw["recommendations"] as? [[String: Any]],
      recommendations.allSatisfy({ Set($0.keys) == Set(["text", "actionID"]) })
    else { throw AIReportFailure.invalidResponse }
    let wire = try ReportWireInput(input)
    let received = try AIReportPolicy.decoder().decode(ReportResult.self, from: data)
    try validate(received, input: wire.validationInput, now: now)
    let result = try wire.restore(received)
    try validate(result, input: input, now: now)
    return result
  }
  static func validate(_ result: ReportResult, input: ReportInput, now: Date) throws {
    guard result.schemaVersion == 1, !result.isLocalFallback,
      UUID(uuidString: result.reportID) != nil, result.inputFingerprint == input.inputFingerprint,
      result.model == AIReportPolicy.model, result.promptVersion == AIReportPolicy.promptVersion,
      result.summary == ReportText.summary(input), result.observations.count <= 3,
      result.recommendations.count <= 3, result.generatedAt <= now.addingTimeInterval(60),
      result.generatedAt >= now.addingTimeInterval(-AIReportPolicy.maximumInputAge),
      result.validUntil > now, result.validUntil > result.generatedAt,
      result.validUntil <= result.generatedAt.addingTimeInterval(AIReportPolicy.reportLifetime + 1),
      result.validUntil <= input.asOf.addingTimeInterval(AIReportPolicy.maximumInputAge + 1),
      Set(result.observations.flatMap(\.evidenceIDs)).count == result.observations.count,
      Set(result.recommendations.map(\.actionID)).count == result.recommendations.count
    else { throw AIReportFailure.invalidResponse }
    for observation in result.observations {
      guard observation.evidenceIDs.count == 1,
        let fact = input.facts.first(where: { $0.id == observation.evidenceIDs[0] }),
        observation.text == ReportText.observation(fact)
      else { throw AIReportFailure.invalidResponse }
    }
    for recommendation in result.recommendations {
      guard let candidate = input.candidates.first(where: { $0.actionID == recommendation.actionID }),
        recommendation.text == ReportText.action(candidate.action)
      else { throw AIReportFailure.invalidResponse }
    }
  }
}
