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
  /// The report card shows a scope-specific preview. The full dependency closure stays in
  /// `facts(_:)` for the evidence page and remote contract.
  static func highlights(_ input: ReportInput) -> [MetricFact] {
    let selected = facts(input)
    let priorities: [String]
    switch input.reportType {
    case .today:
      let feelingRecorded = selected.contains { $0.metric == "recovery.feeling" && $0.value != nil }
      priorities = ["recommendation.availableToday", "recovery.feeling"]
        + (input.goalDirection.map { ["recommendation.goal.\($0.rawValue)"] } ?? [])
        + (feelingRecorded ? [] : ["recommendation.feeling.tired"])
    case .trend:
      priorities = ["weight.smoothed", "weight.weeklyChangePercent", "diet.completeDays"]
    case .recovery:
      priorities = ["recovery.feeling", "recovery.sleepFeeling", "recovery.readiness"]
    case .weekly:
      priorities = ["diet.completeDays", "weight.weeklyChangePercent", "recovery.feeling"]
    }
    let preferred = priorities.compactMap { metric in
      selected.filter { $0.metric == metric }.sorted {
        if ($0.value != nil) != ($1.value != nil) { return $0.value != nil }
        if metric == "recovery.readiness", let left = $0.value, let right = $1.value,
          left != right { return left < right }
        if $0.window.end != $1.window.end { return $0.window.end > $1.window.end }
        return $0.id < $1.id
      }.first
    }
    return Array((preferred + selected.filter { fact in
      !preferred.contains(where: { $0.id == fact.id })
    }).prefix(3))
  }
  private static func isTrendBucket(_ fact: MetricFact) -> Bool {
    // B deliberately preserves whole calendar buckets and hashes each derived fact's content.
    // Its sources describe the original readings, so they can be manual, HealthKit or empty.
    let units: [String: MetricUnit] = ["weight.representative": .kilograms, "weight.smoothed": .kilograms,
      "energy.initialEstimate": .kilocalories, "weight.targetWeeklyChangePercent": .percentPerWeek]
    let prefix = "trend.\(fact.metric)."
    return units[fact.metric] == fact.unit && fact.id.hasPrefix(prefix)
      && String(fact.id.dropFirst(prefix.count)).range(of: "^[a-f0-9]{20}$", options: .regularExpression) != nil
      && fact.sources.allSatisfy { $0.kind == .manual || $0.kind == .healthKit }
      && (fact.metric == "weight.smoothed" || fact.value != nil)
  }
  static func wireWindow(_ fact: MetricFact, asOf: Date) throws -> AnalysisWindow {
    guard fact.window.start <= fact.window.end else { throw AIReportFailure.invalidInput }
    guard fact.window.end > asOf else { return fact.window }
    guard fact.window.start <= asOf else { throw AIReportFailure.invalidInput }
    let duration = fact.window.end.timeIntervalSince(fact.window.start)
    if isTrendBucket(fact) {
      // Only the last, unfinished day can extend past asOf. Smoothing can start many days ago.
      // Calendar days can be 22–26 hours across time-zone transitions; never assume UTC midnight.
      guard fact.window.end.timeIntervalSince(asOf) <= 26 * 3600,
        fact.metric == "weight.smoothed" || (22 * 3600...26 * 3600).contains(duration)
      else { throw AIReportFailure.invalidInput }
    } else {
      // F labels observed recommendation context with a whole local day as well.
      guard fact.metric.hasPrefix("recommendation."),
        fact.sources.contains(where: { $0.kind == .calculation && $0.identifier == "trainote.recommendations" }),
        duration <= 26 * 3600
      else { throw AIReportFailure.invalidInput }
    }
    // Clip the transport copy only. Every other future observation, even within a minute, fails.
    return .init(start: fact.window.start, end: asOf)
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
  static func localSummary(_ input: ReportInput) -> String {
    switch input.reportType {
    case .today:
      return "今日安排与体感来自当前记录；请结合报告依据查看可用事实。"
    case .trend:
      let metrics = Set(input.facts.filter { $0.value != nil }.map(\.metric))
      if !metrics.contains("weight.weeklyChangePercent") {
        let rules = TrendRules()
        return "趋势记录不足：需至少 \(Int(rules.minimumSpanDays)) 天跨度、\(rules.minimumWeightDays) 个称重日，且最近两周各至少 \(rules.minimumWeightDaysPerWeek) 天。"
      }
      return "趋势重点查看体重变化和截至昨天的饮食完整记录。"
    case .recovery:
      return "恢复重点查看今日体感、睡眠与肌群记录；缺失项保持未知。"
    case .weekly:
      return "本周回顾结合体重变化、饮食完整度与恢复记录。"
    }
  }
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
      var meaning = semanticValue(fact)
      if let value = fact.value {
        switch fact.metric {
        case "recommendation.selectedPlan":
          if value == 1 { meaning = "本次模板：已选择" }
        case "recommendation.significantSoreness":
          if value == 0 || value == 1 { meaning = value == 1 ? "明显酸痛：有" : "明显酸痛：无" }
        case "recovery.residualLoad", "recovery.lastSessionLoad":
          meaning = "负荷值：\(number)"
        default:
          if fact.metric.hasPrefix("recommendation.systemic."), value == 1,
            let state = RecoveryState(rawValue: String(fact.metric.dropFirst("recommendation.systemic.".count))) {
            switch state {
            case .ready: meaning = "全身状态：状态较好"
            case .moderate: meaning = "全身状态：留意体感与近期变化"
            case .low: meaning = "全身状态：优先恢复"
            case .limited: meaning = "全身状态：训练受限"
            case .unknown: break
            }
          } else if fact.metric.hasPrefix("recovery."), fact.metric.hasSuffix(".soreness") {
            switch value {
            case 0: meaning = "酸痛：无"
            case 1: meaning = "酸痛：轻微"
            case 2: meaning = "酸痛：明显"
            default: break
            }
          } else if fact.metric.hasPrefix("recovery."),
            fact.metric.hasSuffix(".pain") || fact.metric.hasSuffix(".movementLimitation"),
            value == 0 || value == 1 {
            let name = fact.metric.hasSuffix(".pain") ? "疼痛" : "活动限制"
            meaning = "\(name)：\(value == 1 ? "有" : "无")"
          } else if fact.metric.hasPrefix("recovery.systemic."),
            fact.metric.hasSuffix(".sustainedDeviation"), value == 0 || value == 1 {
            meaning = "连续偏离个人基线：\(value == 1 ? "是" : "否")"
          }
        }
      }
      if let meaning {
        text = text.replacingOccurrences(of: "记录值：{{fact:\(fact.id)}}", with: meaning)
          .replacingOccurrences(of: "记录仍有缺失或估计：{{fact:\(fact.id)}}", with: meaning)
        continue
      }
      let units: [MetricUnit: String] = [.kilograms: "kg", .centimeters: "cm", .kilocalories: "kcal",
        .grams: "g", .seconds: "秒", .milliseconds: "ms", .beatsPerMinute: "次/分", .count: "次",
        .percent: "%", .score: "分", .kilogramsPerWeek: "kg/周", .percentPerWeek: "%/周", .none: ""]
      let countUnit: String? = switch fact.metric {
      case "recommendation.trainingDaysPerWeek": "天/周"
      case "recommendation.painOrLimitation": "个肌群"
      case "recommendation.recentWorkingSets": "组"
      default: nil
      }
      text = text.replacingOccurrences(of: "{{fact:\(fact.id)}}",
        with: "\(number)\(fact.value == nil ? "" : countUnit ?? units[fact.unit] ?? "")")
    }
    return text
  }

  private static func semanticValue(_ fact: MetricFact) -> String? {
    guard let value = fact.value else { return nil }
    if fact.metric.hasPrefix("recommendation.goal.") {
      switch String(fact.metric.dropFirst("recommendation.goal.".count)) {
      case "maintain": return "目标：维持"
      case "lose": return "目标：减脂"
      case "gain": return "目标：增肌"
      default: return nil
      }
    }
    if fact.metric == "recovery.feeling" {
      return "今日体感：\(value == 0 ? "疲惫" : value == 1 ? "一般" : "良好")"
    }
    if fact.metric == "recovery.sleepFeeling" {
      return "主观睡眠：\(value == 0 ? "较差" : value == 1 ? "一般" : "良好")"
    }
    if fact.metric == "recommendation.feeling.tired" {
      return value == 1 ? "今日体感：疲惫" : "今日体感未标记疲惫"
    }
    if fact.metric == "recommendation.availableToday" {
      return value == 1 ? "日程：允许训练" : "日程：未安排训练"
    }
    if fact.metric == "diet.completeDays" {
      return "截至昨天的 14 天：\(Int(value)) 天已确认完整"
    }
    return nil
  }
}

struct LocalReportGenerator: ReportGenerating {
  func generate(_ input: ReportInput) async throws -> ReportResult { make(input) }
  func make(_ input: ReportInput) -> ReportResult {
    .init(reportID: "local-" + UUID().uuidString, inputFingerprint: input.inputFingerprint,
      model: "local", promptVersion: AIReportPolicy.promptVersion, summary: ReportText.localSummary(input),
      observations: ReportFactSelection.highlights(input).map { .init(text: ReportText.observation($0), evidenceIDs: [$0.id]) },
      recommendations: input.candidates.filter {
        input.reportType != .trend || $0.action == .reviewNutrition
      }.prefix(3).map {
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
