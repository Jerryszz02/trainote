import Foundation

enum OnDeviceReportPolicy {
  // The identity is also the cache namespace; changing weights or prompts invalidates current results.
  static let model = "qwen3-0.6b-c1899de-Q4_K_M-llama-b11912"
  static let promptVersion = "on-device-selection-v1"
  static let maximumTokens = 256
  static let maximumPromptBytes = 12_000
  static let maximumFacts = 20
}

/// A bounded, value-only selection task. Notes, source identifiers and raw samples stay outside it.
struct OnDeviceReportRequest {
  let input: ReportInput
  let facts: [MetricFact]
  let candidates: [RecommendationCandidate]
  let prompt: String
  let grammar: String

  init(_ input: ReportInput, maximumFacts: Int = OnDeviceReportPolicy.maximumFacts) throws {
    try ReportWireInput.validateLocal(input)
    self.input = input
    candidates = input.candidates.filter { input.reportType != .trend || $0.action == .reviewNutrition }
      .sorted { $0.actionID < $1.actionID }
    let reasons = Set(candidates.flatMap(\.reasonFactIDs))
    guard (1...OnDeviceReportPolicy.maximumFacts).contains(maximumFacts) else { throw AIReportFailure.invalidInput }
    func belongsToScope(_ fact: MetricFact) -> Bool {
      // Trend reports never offer unrelated recovery facts, even when the record is sparse.
      input.reportType != .trend || ["weight.", "diet.", "energy.", "recommendation.goal."].contains { fact.metric.hasPrefix($0) }
    }
    let highlights = ReportFactSelection.highlights(input).filter(belongsToScope)
    // Keep every candidate's evidence, then one recent summary per metric. Never cut a reason set.
    let summaries = Dictionary(grouping: ReportFactSelection.facts(input).filter(belongsToScope), by: \.metric)
      .values.compactMap { values in
        values.sorted {
          if $0.window.end != $1.window.end { return $0.window.end > $1.window.end }
          if $0.metric == "recovery.readiness", let a = $0.value, let b = $1.value, a != b { return a < b }
          return $0.id < $1.id
        }.first
      }.sorted { $0.id < $1.id }
    var chosen = input.facts.filter { reasons.contains($0.id) }.sorted { $0.id < $1.id }
    guard chosen.count <= maximumFacts else { throw AIReportFailure.invalidInput }
    for fact in highlights + summaries where !chosen.contains(where: { $0.id == fact.id }) {
      if chosen.count < maximumFacts { chosen.append(fact) }
    }
    facts = chosen
    let aliases = Dictionary(uniqueKeysWithValues: chosen.enumerated().map { ($0.element.id, "f\($0.offset)") })
    let factRows: [[String: Any]] = chosen.enumerated().map { index, fact in
      ["id": "f\(index)", "metric": fact.metric, "value": fact.value as Any? ?? NSNull(),
       "unit": fact.unit.rawValue, "quality": fact.quality.map(\.rawValue)]
    }
    let actionRows: [[String: Any]] = try candidates.enumerated().map { index, candidate in
      ["id": "a\(index)", "action": candidate.action.rawValue,
       "facts": try candidate.reasonFactIDs.map { id -> String in
         guard let alias = aliases[id] else { throw AIReportFailure.invalidInput }
         return alias
       }]
    }
    let payload: [String: Any] = ["scope": input.reportType.rawValue, "facts": factRows,
      "actions": actionRows, "missing": input.missingData]
    let json = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
    let text = String(decoding: json, as: UTF8.self)
    prompt = """
    <|im_start|>system
    Select useful facts and approved actions for a fitness report. Return only JSON with factIDs and actionIDs, each at most 3 unique IDs. Prioritize pain, limitations, poor recovery and missing evidence before routine positive facts. Match the report scope. Unknown is not zero; uncertain facts remain uncertain. Select only IDs from the supplied lists. Actions are already approved by code; do not create actions, numbers or advice. If no relevant item exists, return an empty array. /no_think
    <|im_end|>
    <|im_start|>user
    \(text)
    <|im_end|>
    <|im_start|>assistant
    <think>

    </think>

    """
    guard prompt.utf8.count <= OnDeviceReportPolicy.maximumPromptBytes else { throw AIReportFailure.invalidInput }
    func arrayRule(_ name: String, ids: [String]) -> String {
      guard !ids.isEmpty else { return "\(name) ::= \"[\" ws \"]\"" }
      let values = ids.map { "\"\\\"\($0)\\\"\"" }.joined(separator: " | ")
      return "\(name)-id ::= \(values)\n\(name) ::= \"[\" ws (\(name)-id (ws \",\" ws \(name)-id (ws \",\" ws \(name)-id)?)?)? ws \"]\""
    }
    grammar = """
    root ::= "{" ws "\\\"factIDs\\\"" ws ":" ws facts ws "," ws "\\\"actionIDs\\\"" ws ":" ws actions ws "}" ws
    ws ::= [ \\t\\n\\r]*
    \(arrayRule("facts", ids: chosen.indices.map { "f\($0)" }))
    \(arrayRule("actions", ids: candidates.indices.map { "a\($0)" }))
    """
  }

  func result(from output: String, now: Date) throws -> ReportResult {
    let data = Data(output.utf8)
    guard data.count <= 4096,
      let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(value.keys) == ["factIDs", "actionIDs"],
      let factIDs = value["factIDs"] as? [String], let actionIDs = value["actionIDs"] as? [String],
      factIDs.count <= 3, actionIDs.count <= 3,
      Set(factIDs).count == factIDs.count, Set(actionIDs).count == actionIDs.count
    else { throw AIReportFailure.invalidResponse }
    let factMap = Dictionary(uniqueKeysWithValues: facts.enumerated().map { ("f\($0.offset)", $0.element) })
    let actionMap = Dictionary(uniqueKeysWithValues: candidates.enumerated().map { ("a\($0.offset)", $0.element) })
    let observations = try factIDs.map { alias -> ReportObservation in
      guard let fact = factMap[alias] else { throw AIReportFailure.invalidResponse }
      return .init(text: ReportText.observation(fact), evidenceIDs: [fact.id])
    }
    let recommendations = try actionIDs.map { alias -> ReportRecommendation in
      guard let candidate = actionMap[alias] else { throw AIReportFailure.invalidResponse }
      return .init(text: ReportText.action(candidate.action), actionID: candidate.actionID)
    }
    let result = ReportResult(reportID: UUID().uuidString, inputFingerprint: input.inputFingerprint,
      model: OnDeviceReportPolicy.model, promptVersion: OnDeviceReportPolicy.promptVersion,
      summary: ReportText.summary(input), observations: observations, recommendations: recommendations,
      generatedAt: now, validUntil: min(now.addingTimeInterval(AIReportPolicy.reportLifetime),
        input.asOf.addingTimeInterval(AIReportPolicy.maximumInputAge)), isLocalFallback: false)
    try ReportResultValidator.validateOnDevice(result, input: input, now: now)
    return result
  }
}

struct OnDeviceReportGenerator: ReportGenerating {
  let runtime: any OnDeviceModelRuntime
  var clock: @Sendable () -> Date = { .now }

  func generate(_ input: ReportInput) async throws -> ReportResult {
    try Task.checkCancellation()
    var request = try OnDeviceReportRequest(input)
    let output: String
    do {
      output = try await runtime.generate(prompt: request.prompt, grammar: request.grammar,
        maximumTokens: OnDeviceReportPolicy.maximumTokens)
    } catch OnDeviceRuntimeError.inputTooLong {
      // One bounded retry may remove optional summaries, never candidate reasons.
      // If the required evidence itself does not fit, construction fails back to rules.
      try Task.checkCancellation()
      request = try OnDeviceReportRequest(input, maximumFacts: 12)
      output = try await runtime.generate(prompt: request.prompt, grammar: request.grammar,
        maximumTokens: OnDeviceReportPolicy.maximumTokens)
    }
    try Task.checkCancellation()
    return try request.result(from: output, now: clock())
  }
}
