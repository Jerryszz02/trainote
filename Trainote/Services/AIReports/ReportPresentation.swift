import Foundation

/// Display projection only: never changes cached results, wire validation or report requests.
enum ReportPresentation {
  static func supports(_ report: ReportResult) -> Bool {
    report.schemaVersion == AnalysisContract.schemaVersion
      && (report.promptVersion == AIReportPolicy.promptVersion || report.promptVersion == "fixture-v1")
  }

  static func summary(_ report: ReportResult) -> String {
    guard supports(report) else { return report.summary }
    let rules = TrendRules()
    let canonical = "趋势记录不足：需至少 \(Int(rules.minimumSpanDays)) 天跨度、\(rules.minimumWeightDays) 个称重日，且最近两周各至少 \(rules.minimumWeightDaysPerWeek) 天。"
    if report.summary == canonical {
      return L10n.text("domain.report.insufficientTrend", Int(rules.minimumSpanDays), rules.minimumWeightDays, rules.minimumWeightDaysPerWeek)
    }
    return recommendation(report.summary)
  }
  static func recommendation(_ text: String) -> String {
    switch text {
    case "今日安排与体感来自当前记录；请结合报告依据查看可用事实。": L10n.text("domain.report.template.today")
    case "趋势重点查看体重变化和截至昨天的饮食完整记录。": L10n.text("domain.report.template.trend")
    case "恢复重点查看今日体感、睡眠与肌群记录；缺失项保持未知。": L10n.text("domain.report.template.recovery")
    case "本周回顾结合体重变化、饮食完整度与恢复记录。": L10n.text("domain.report.template.weekly")
    case "可保持原训练计划。": L10n.text("domain.report.template.keepPlan")
    case "可按规则候选减少工作组。": L10n.text("domain.report.template.reduceSets")
    case "可按规则候选增加保留次数。": L10n.text("domain.report.template.increaseRIR")
    case "可考虑调换训练日。": L10n.text("domain.report.template.swapTrainingDay")
    case "可考虑休息。": L10n.text("domain.report.template.rest")
    case "可考虑轻活动。": L10n.text("domain.report.template.lightActivity")
    case "先选择训练模板或目标。": L10n.text("domain.report.template.choosePlan")
    case "可复核当前营养目标与执行记录。": L10n.text("domain.report.template.reviewNutrition")
    case "根据当前记录，可查看以下事实与候选建议。": L10n.text("domain.report.template.availableRecords")
    case "当前记录不足，补充记录后再看变化。": L10n.text("domain.report.template.insufficientRecords")
    case "合成数据示例": L10n.text("domain.report.syntheticExample")
    default: text
    }
  }
  static func display(_ observation: ReportObservation, facts: [MetricFact]) -> String {
    guard let fact = facts.first(where: { observation.evidenceIDs == [$0.id] }),
      observation.text == ReportText.observation(fact) else { return observation.text }
    var text = observation.text
    for fact in facts where observation.evidenceIDs.contains(fact.id) {
      let number = fact.value.map { $0.formatted(.number.precision(.fractionLength(0...2)).locale(L10n.locale)) } ?? L10n.text("domain.report.unknown")
      var meaning = semanticValue(fact)
      if let value = fact.value {
        switch fact.metric {
        case "recommendation.selectedPlan":
          if value == 1 { meaning = L10n.text("domain.report.template.selected") }
        case "recommendation.significantSoreness":
          if value == 0 || value == 1 { meaning = value == 1 ? L10n.text("domain.report.significant.soreness.yes") : L10n.text("domain.report.significant.soreness.no") }
        case "recovery.residualLoad", "recovery.lastSessionLoad":
          meaning = L10n.text("domain.report.load", number)
        default:
          if fact.metric.hasPrefix("recommendation.systemic."), value == 1,
            let state = RecoveryState(rawValue: String(fact.metric.dropFirst("recommendation.systemic.".count))) {
            switch state {
            case .ready: meaning = L10n.text("domain.report.overall.recovery.ready")
            case .moderate: meaning = L10n.text("domain.report.overall.recovery.monitor.how.you.feel.and.recent.changes")
            case .low: meaning = L10n.text("domain.report.overall.recovery.prioritize.recovery")
            case .limited: meaning = L10n.text("domain.report.overall.recovery.training.limited")
            case .unknown: break
            }
          } else if fact.metric.hasPrefix("recovery."), fact.metric.hasSuffix(".soreness") {
            switch value {
            case 0: meaning = L10n.text("domain.report.soreness.none")
            case 1: meaning = L10n.text("domain.report.soreness.mild")
            case 2: meaning = L10n.text("domain.report.soreness.significant")
            default: break
            }
          } else if fact.metric.hasPrefix("recovery."),
            fact.metric.hasSuffix(".pain") || fact.metric.hasSuffix(".movementLimitation"),
            value == 0 || value == 1 {
            let name = fact.metric.hasSuffix(".pain") ? L10n.text("domain.report.pain") : L10n.text("domain.report.movement.limitation")
            meaning = L10n.text("domain.report.boolean", name, value == 1 ? L10n.text("domain.report.present") : L10n.text("domain.report.absent"))
          } else if fact.metric.hasPrefix("recovery.systemic."),
            fact.metric.hasSuffix(".sustainedDeviation"), value == 0 || value == 1 {
            meaning = L10n.text("domain.report.deviation", value == 1 ? L10n.text("domain.report.yes") : L10n.text("domain.report.no"))
          }
        }
      }
      if let meaning {
        text = text.replacingOccurrences(of: "记录值：{{fact:\(fact.id)}}", with: meaning)
          .replacingOccurrences(of: "记录仍有缺失或估计：{{fact:\(fact.id)}}", with: meaning)
        continue
      }
      text = text.replacingOccurrences(of: "{{fact:\(fact.id)}}",
        with: fact.value.map { numberWithUnit(number, value: $0, fact: fact) } ?? number)
    }
    if text.hasPrefix("暂无可用记录：") {
      return L10n.text("domain.report.noRecord", String(text.dropFirst("暂无可用记录：".count).dropLast()))
    }
    if text.hasPrefix("记录值：") {
      return L10n.text("domain.report.record", String(text.dropFirst("记录值：".count).dropLast()))
    }
    if text.hasPrefix("记录仍有缺失或估计：") {
      return L10n.text("domain.report.estimated", String(text.dropFirst("记录仍有缺失或估计：".count).dropLast()))
    }
    if text.hasSuffix("。") { text.removeLast(); text += L10n.language == .english ? "." : "。" }
    return text
  }

  /// Keep the localized number intact, including fractional scores. The singular selection uses
  /// the actual value rather than converting it to an integer or parsing its displayed spelling.
  private static func numberWithUnit(_ number: String, value: Double, fact: MetricFact) -> String {
    let countKey: String? = switch fact.metric {
    case "recommendation.trainingDaysPerWeek": "domain.report.quantity.daysPerWeek"
    case "recommendation.painOrLimitation": "domain.report.quantity.muscleGroups"
    case "recommendation.recentWorkingSets": "domain.report.quantity.sets"
    default: nil
    }
    if let countKey { return L10n.text(countKey + (value == 1 ? ".one" : ".other"), number) }
    switch fact.unit {
    case .count: return L10n.text(value == 1 ? "domain.report.quantity.count.one" : "domain.report.quantity.count.other", number)
    case .score: return L10n.text(value == 1 ? "domain.report.quantity.score.one" : "domain.report.quantity.score.other", number)
    case .kilograms: return L10n.text("domain.report.quantity.kilograms", number)
    case .centimeters: return L10n.text("domain.report.quantity.centimeters", number)
    case .kilocalories: return L10n.text("domain.report.quantity.kilocalories", number)
    case .grams: return L10n.text("domain.report.quantity.grams", number)
    case .seconds: return L10n.text("domain.report.quantity.seconds", number)
    case .milliseconds: return L10n.text("domain.report.quantity.milliseconds", number)
    case .beatsPerMinute: return L10n.text("domain.report.quantity.beatsPerMinute", number)
    case .percent: return L10n.text("domain.report.quantity.percent", number)
    case .kilogramsPerWeek: return L10n.text("domain.report.quantity.kilogramsPerWeek", number)
    case .percentPerWeek: return L10n.text("domain.report.quantity.percentPerWeek", number)
    case .none: return number
    }
  }

  private static func semanticValue(_ fact: MetricFact) -> String? {
    guard let value = fact.value else { return nil }
    if fact.metric.hasPrefix("recommendation.goal.") {
      switch String(fact.metric.dropFirst("recommendation.goal.".count)) {
      case "maintain": return L10n.text("domain.report.goal.maintain")
      case "lose": return L10n.text("domain.report.goal.lose.fat")
      case "gain": return L10n.text("domain.report.goal.gain.muscle")
      default: return nil
      }
    }
    if fact.metric == "recovery.feeling" {
      return L10n.text("domain.report.feeling", value == 0 ? L10n.text("domain.report.tired") : value == 1 ? L10n.text("domain.report.normal") : L10n.text("domain.report.good"))
    }
    if fact.metric == "recovery.sleepFeeling" {
      return L10n.text("domain.report.sleep", value == 0 ? L10n.text("domain.report.poor") : value == 1 ? L10n.text("domain.report.normal") : L10n.text("domain.report.good"))
    }
    if fact.metric == "recommendation.feeling.tired" {
      return value == 1 ? L10n.text("domain.report.today.s.feeling.tired") : L10n.text("domain.report.today.s.feeling.is.not.marked.tired")
    }
    if fact.metric == "recommendation.availableToday" {
      return value == 1 ? L10n.text("domain.report.schedule.training.available") : L10n.text("domain.report.schedule.no.training.scheduled")
    }
    if fact.metric == "diet.completeDays" {
      return L10n.text("domain.report.completeDays", Int(value))
    }
    return nil
  }
}
