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
}

enum AIReportFailure: Error, Equatable {
  case unavailable, invalidInput, invalidResponse, stale, cancelled, storage
  case consentRequired, revocationPending, deviceUnavailable, server(Int)
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

  init(_ input: ReportInput) throws {
    let ids = Set(input.facts.map(\.id))
    guard input.schemaVersion == 1, input.knowledgeVersion == AIReportPolicy.knowledgeVersion,
      input.inputFingerprint.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
      input.facts.count <= 100, ids.count == input.facts.count,
      input.candidates.count <= 12,
      Set(input.candidates.map(\.actionID)).count == input.candidates.count,
      (1...8).contains(input.calculationVersions.count),
      input.calculationVersions.allSatisfy(AIReportPolicy.identifier),
      input.missingData.count <= 32, input.missingData.allSatisfy(AIReportPolicy.identifier),
      input.facts.allSatisfy({
        AIReportPolicy.identifier($0.id) && AIReportPolicy.identifier($0.metric)
          && ($0.value == nil || ($0.value!.isFinite && abs($0.value!) <= 1e12))
          && $0.window.start <= $0.window.end && $0.window.end <= input.asOf.addingTimeInterval(60)
          && $0.quality.count <= 12
      }), input.candidates.allSatisfy({
        AIReportPolicy.identifier($0.actionID) && $0.reasonFactIDs.allSatisfy(ids.contains)
          && $0.muscleIDs.count <= 11 && $0.reasonFactIDs.count <= 100
      })
    else { throw AIReportFailure.invalidInput }
    schemaVersion = input.schemaVersion
    reportType = input.reportType
    asOf = input.asOf
    inputFingerprint = input.inputFingerprint
    facts = input.facts.map { .init(id: $0.id, metric: $0.metric, value: $0.value,
      unit: $0.unit, window: $0.window, quality: $0.quality) }
    // An excluded candidate is never exposed to the provider; no model parameter can un-exclude it.
    candidates = input.candidates.filter { $0.exclusionCodes.isEmpty }.map {
      .init(actionID: $0.actionID, action: $0.action, muscleIDs: $0.muscleIDs, reasonFactIDs: $0.reasonFactIDs)
    }
    goalDirection = input.goalDirection
    knowledgeVersion = input.knowledgeVersion
    calculationVersions = input.calculationVersions
    missingData = input.missingData
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
    input.facts.contains { $0.value != nil }
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
      observations: input.facts.prefix(3).map { .init(text: ReportText.observation($0), evidenceIDs: [$0.id]) },
      recommendations: input.candidates.filter { $0.exclusionCodes.isEmpty }.prefix(3).map {
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
    let result = try AIReportPolicy.decoder().decode(ReportResult.self, from: data)
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
        candidate.exclusionCodes.isEmpty, recommendation.text == ReportText.action(candidate.action)
      else { throw AIReportFailure.invalidResponse }
    }
  }
}
