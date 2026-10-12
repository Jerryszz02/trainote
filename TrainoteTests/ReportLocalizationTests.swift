import XCTest
@testable import Trainote

@MainActor
final class ReportLocalizationTests: XCTestCase {
  func testPresentationSwitchDoesNotChangeReportProtocolOrStoredResult() throws {
    let previous = LanguageSettings.shared.preference
    defer { LanguageSettings.shared.preference = previous }
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ai-report-contract", withExtension: "json"))
    let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let input = try AIReportPolicy.decoder().decode(ReportInput.self,
      from: JSONSerialization.data(withJSONObject: try XCTUnwrap(fixture["localInput"])))
    LanguageSettings.shared.preference = .simplifiedChinese
    let report = LocalReportGenerator().make(input)
    let wireBefore = try AIReportPolicy.encoder().encode(ReportWireInput(input))
    let storedBefore = try AIReportPolicy.encoder().encode(report)
    let chineseSummary = ReportPresentation.summary(report)
    LanguageSettings.shared.preference = .english
    XCTAssertNotEqual(ReportPresentation.summary(report), chineseSummary)
    XCTAssertEqual(LocalReportGenerator().make(input).summary, report.summary)
    XCTAssertEqual(try AIReportPolicy.encoder().encode(ReportWireInput(input)), wireBefore)
    XCTAssertEqual(try AIReportPolicy.encoder().encode(report), storedBefore)
    XCTAssertEqual(ReportText.action(.rest), "可考虑休息。")
  }

  func testUnknownHistoricalTextIsPreserved() {
    let previous = LanguageSettings.shared.preference
    defer { LanguageSettings.shared.preference = previous }
    LanguageSettings.shared.preference = .english
    var unknownVersion = LocalReportGenerator().make(AnalysisFixtures.report)
    unknownVersion.promptVersion = "future-template-v2"
    XCTAssertEqual(ReportPresentation.summary(unknownVersion), unknownVersion.summary)
    XCTAssertFalse(ReportPresentation.supports(unknownVersion))
    let text = "用户原文：早上跑步以后休息"
    XCTAssertEqual(ReportPresentation.recommendation(text), text)
    XCTAssertEqual(ReportPresentation.display(.init(text: text, evidenceIDs: []), facts: []), text)
  }

  func testBackupErrorRendersCurrentLanguageWithoutChangingReason() {
    let previous = LanguageSettings.shared.preference
    defer { LanguageSettings.shared.preference = previous }
    let error = BackupArchiveError.invalid("存在重复 ID。")
    LanguageSettings.shared.preference = .simplifiedChinese
    XCTAssertEqual(error.errorDescription, "备份无效：存在重复 ID。")
    LanguageSettings.shared.preference = .english
    XCTAssertEqual(error.errorDescription, "Invalid backup: Duplicate IDs exist.")
    XCTAssertEqual(error, .invalid("存在重复 ID。"))
  }

  func testKnownObservationUsesTranslatedMeaningAndUnknownRemainsVerbatim() {
    let previous = LanguageSettings.shared.preference
    defer { LanguageSettings.shared.preference = previous }
    LanguageSettings.shared.preference = .english
    let fact = MetricFact(id: "feeling", metric: "recovery.feeling", value: 0, unit: .score,
      window: AnalysisFixtures.window, sources: [.manual])
    let canonical = ReportObservation(text: ReportText.observation(fact), evidenceIDs: [fact.id])
    XCTAssertEqual(ReportPresentation.display(canonical, facts: [fact]), "Today’s feeling: Tired.")
    let historical = ReportObservation(text: "旧报告记录值：{{fact:feeling}}", evidenceIDs: [fact.id])
    XCTAssertEqual(ReportPresentation.display(historical, facts: [fact]), historical.text)
  }

  func testReportQuantitiesUseFullLocalizedFormatsWithoutTruncatingScores() {
    let settings = LanguageSettings.shared
    let previous = settings.preference
    let previousLanguages = settings.preferredLanguages
    let previousLocale = settings.regionalLocale
    defer {
      settings.preference = previous
      settings.refreshSystem(preferredLanguages: previousLanguages, regionalLocale: previousLocale)
    }
    settings.refreshSystem(preferredLanguages: ["en-GB"], regionalLocale: Locale(identifier: "en_GB"))
    let cases: [(String, MetricUnit, Double, String, String)] = [
      ("recommendation.recentWorkingSets", .count, 0, "0 sets", "0组"),
      ("recommendation.recentWorkingSets", .count, 1, "1 set", "1组"),
      ("recommendation.recentWorkingSets", .count, 2, "2 sets", "2组"),
      ("recommendation.painOrLimitation", .count, 1, "1 muscle group", "1个肌群"),
      ("recommendation.painOrLimitation", .count, 2, "2 muscle groups", "2个肌群"),
      ("recommendation.trainingDaysPerWeek", .count, 1, "1 day/week", "1天/周"),
      ("recommendation.trainingDaysPerWeek", .count, 3, "3 days/week", "3天/周"),
      ("generic.count", .count, 1, "1 count", "1次"),
      ("generic.count", .count, 2, "2 counts", "2次"),
      ("generic.score", .score, 1, "1 point", "1分"),
      ("generic.score", .score, 1.5, "1.5 points", "1.5分"),
      ("generic.score", .score, 0.25, "0.25 points", "0.25分"),
      ("weight", .kilograms, 62.5, "62.5 kg", "62.5kg"),
      ("height", .centimeters, 170, "170 cm", "170cm"),
      ("energy", .kilocalories, 100, "100 kcal", "100kcal"),
      ("protein", .grams, 25, "25 g", "25g"),
      ("duration", .seconds, 60, "60 s", "60秒"),
      ("interval", .milliseconds, 50, "50 ms", "50ms"),
      ("heartRate", .beatsPerMinute, 60, "60 bpm", "60次/分"),
      ("difference", .percent, 2.5, "2.5%", "2.5%"),
      ("weightChange", .kilogramsPerWeek, 0.25, "0.25 kg/week", "0.25kg/周"),
      ("weeklyChange", .percentPerWeek, 0.5, "0.5%/week", "0.5%/周"),
      ("untyped", .none, 1.5, "1.5", "1.5")
    ]
    for (metric, unit, value, english, chinese) in cases {
      let fact = MetricFact(id: metric, metric: metric, value: value, unit: unit,
        window: AnalysisFixtures.window, sources: [.manual])
      let observation = ReportObservation(text: ReportText.observation(fact), evidenceIDs: [fact.id])
      settings.preference = .english
      XCTAssertEqual(ReportPresentation.display(observation, facts: [fact]),
        "Recorded value: \(english).", metric)
      settings.preference = .simplifiedChinese
      XCTAssertEqual(ReportPresentation.display(observation, facts: [fact]), "记录值：\(chinese)。", metric)
      XCTAssertEqual(observation.text, ReportText.observation(fact))
    }
    settings.preference = .english
    let missing = MetricFact(id: "missing", metric: "generic.score", value: nil, unit: .score,
      window: AnalysisFixtures.window, sources: [])
    XCTAssertEqual(ReportPresentation.display(
      .init(text: ReportText.observation(missing), evidenceIDs: [missing.id]), facts: [missing]),
      "No record available: Unknown.")
  }
}
