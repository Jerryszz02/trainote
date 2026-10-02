import Foundation

/// Separate context only: these facts never subtract points from a muscle.
enum RecoverySystemic {
  struct Result {
    var state: RecoveryState
    var facts: [MetricFact]
  }
  static func calculate(_ input: AnalysisInput, feedback: RecoveryFeedback) -> Result {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: input.calendarTimeZone) ?? .gmt
    let today = calendar.startOfDay(for: input.asOf)
    var output: [MetricFact] = feedback.facts.filter {
      ["recovery.feeling", "recovery.sleepFeeling"].contains($0.id)
    }
    var sustained = false
    var hasContext = feedback.feeling != nil || feedback.sleepFeeling != nil
    for metric in ["sleep.duration", "restingHeartRate", "heartRateVariabilitySDNN"] {
      let available = input.health.facts.filter {
        $0.metric == metric && $0.value.map { $0.isFinite && $0 > 0 } == true
          && $0.window.end <= input.asOf && $0.window.start <= $0.window.end
      }
      // Foundation embeds product/definition/context in the stable HRV fact suffix.
      // Unknown ID formats remain separate and cannot accidentally establish a mixed baseline.
      let groups = Dictionary(grouping: available) { seriesKey($0) }
      let sortedKeys = groups.keys.sorted { lhs, rhs in
        let a = preferredRank(groups[lhs]!, preferences: input.preferences)
        let b = preferredRank(groups[rhs]!, preferences: input.preferences)
        if a != b { return a < b }
        let aDate = groups[lhs]!.map(\.window.end).max()!
        let bDate = groups[rhs]!.map(\.window.end).max()!
        return aDate == bDate ? lhs < rhs : aDate > bDate
      }
      guard let key = sortedKeys.first, let group = groups[key] else { continue }
      let byDay = Dictionary(grouping: group) { calendar.startOfDay(for: $0.window.end) }
      guard let latestDay = byDay.keys.max(),
        (calendar.dateComponents([.day], from: latestDay, to: today).day ?? 100) <= 1
      else { continue }
      let recentStart = calendar.date(byAdding: .day, value: -2, to: latestDay)!
      let baselineStart = calendar.date(byAdding: .day, value: -28, to: latestDay)!
      let baselineFacts = group.filter {
        $0.window.end >= baselineStart && $0.window.end < recentStart
      }
      let baselineDays = Dictionary(grouping: baselineFacts) {
        calendar.startOfDay(for: $0.window.end)
      }
      let latestFacts = byDay[latestDay]!.sorted { $0.id < $1.id }
      let prefix = "recovery.systemic.\(metric)"
      func derived(
        _ suffix: String, value: Double?, unit: MetricUnit, facts: [MetricFact],
        quality: [DataQualityFlag] = []
      ) -> MetricFact {
        .init(
          id: "\(prefix).\(suffix)", metric: "\(prefix).\(suffix)", value: value, unit: unit,
          window: .init(
            start: facts.map(\.window.start).min() ?? baselineStart,
            end: facts.map(\.window.end).max() ?? input.asOf),
          sources: RecoveryEvidence.sources(facts),
          dependencies: RecoveryEvidence.dependencies(
            facts.flatMap {
              $0.dependencies + [.init(kind: .metricFact, id: $0.id)]
            }), quality: RecoveryEvidence.quality(quality + facts.flatMap(\.quality)))
      }
      let latest = mean(latestFacts)
      output.append(derived("latest", value: latest, unit: latestFacts[0].unit, facts: latestFacts))
      guard baselineDays.count >= 14 else {
        output.append(
          derived(
            "baseline", value: nil, unit: latestFacts[0].unit,
            facts: baselineFacts, quality: [.insufficientHistory]))
        continue
      }
      let baseline = baselineDays.values.map { mean($0) }.reduce(0, +) / Double(baselineDays.count)
      output.append(
        derived("baseline", value: baseline, unit: latestFacts[0].unit, facts: baselineFacts))
      output.append(
        derived(
          "deviationPercent", value: 100 * (latest / baseline - 1), unit: .percent,
          facts: baselineFacts + latestFacts, quality: [.estimated]))
      if metric == "sleep.duration" {
        // Compare the recorded sleep-window end time, not a claim of measured sleep architecture.
        func angle(_ date: Date) -> Double {
          let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
          let seconds = Double(
            (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0))
          return seconds / 86_400 * 2 * .pi
        }
        let angles = baselineDays.values.compactMap { $0.map(\.window.end).max() }.map(angle)
        let center = atan2(angles.map(sin).reduce(0, +), angles.map(cos).reduce(0, +))
        let latestAngle = angle(latestFacts.map(\.window.end).max()!)
        let shift = atan2(sin(latestAngle - center), cos(latestAngle - center)) / (2 * .pi) * 86_400
        output.append(
          derived(
            "endTimeShift", value: shift, unit: .seconds,
            facts: baselineFacts + latestFacts, quality: [.estimated]))
      }
      hasContext = true
      let days = (0...2).map { calendar.date(byAdding: .day, value: -$0, to: latestDay)! }
      let recentFacts = days.flatMap { byDay[$0] ?? [] }
      let consecutive = days.allSatisfy { day in
        guard let values = byDay[day] else { return false }
        let ratio = mean(values) / baseline
        switch metric {
        case "sleep.duration": return ratio < 0.85
        case "restingHeartRate": return ratio > 1.10
        default: return ratio < 0.80
        }
      }
      sustained = sustained || consecutive
      output.append(
        derived(
          "sustainedDeviation", value: consecutive ? 1 : 0, unit: .none,
          facts: baselineFacts + recentFacts, quality: [.estimated]))
    }
    if let latest = input.health.externalWorkouts.filter({
      $0.start <= $0.end && $0.end <= input.asOf
        && $0.end >= input.asOf.addingTimeInterval(-28 * 86_400)
    }).sorted(by: { $0.end == $1.end ? $0.id.uuidString < $1.id.uuidString : $0.end < $1.end }).last
    {
      output.append(
        .init(
          id: "recovery.systemic.externalWorkout", metric: "recovery.externalWorkoutDuration",
          value: latest.end.timeIntervalSince(latest.start), unit: .seconds,
          window: .init(start: latest.start, end: latest.end), sources: [latest.source],
          dependencies: [
            .init(kind: .healthSample, id: latest.id.uuidString, healthType: .workout)
          ],
          quality: latest.possibleDuplicateIDs.isEmpty ? [.partial] : [.partial, .sourceConflict]))
    }
    let state: RecoveryState
    if sustained && feedback.feeling == .tired {
      state = .low
    } else if feedback.feeling == .tired || feedback.sleepFeeling == .poor || sustained {
      state = .moderate
    } else if hasContext {
      state = .ready
    } else {
      state = .unknown
    }
    return .init(state: state, facts: output)
  }

  static func seriesKey(_ fact: MetricFact) -> String {
    let source = fact.sources.map { "\($0.identifier)|\($0.version ?? "")" }.sorted().joined(
      separator: ";")
    if fact.metric == "heartRateVariabilitySDNN" || fact.metric == "restingHeartRate" {
      let prefix = "health.\(fact.metric)."
      guard fact.id.hasPrefix(prefix) else { return fact.id }
      let suffix = String(fact.id.dropFirst(prefix.count))
      let parts = suffix.split(separator: "|", omittingEmptySubsequences: false)
      guard parts.count == 5, parts[0].count == 10 else { return fact.id }
      return "\(fact.metric)|\(source)|\(parts.dropFirst().joined(separator: "|"))"
    }
    return "\(fact.metric)|\(source)"
  }
  private static func preferredRank(_ facts: [MetricFact], preferences: AnalysisPreferencesValue)
    -> Int
  {
    facts.flatMap(\.sources).compactMap {
      preferences.preferredHealthSourceIDs.firstIndex(of: $0.identifier)
    }.min() ?? Int.max
  }
  private static func mean(_ facts: [MetricFact]) -> Double {
    facts.compactMap(\.value).reduce(0, +) / Double(facts.count)
  }
}
