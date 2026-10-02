import Foundation

/// Loss-aware, value-only normalization. Does not copy health values into manual persistence.
enum HealthValueMerge {
  static func weights(
    manual: [ManualWeightValue], health: HealthDataSnapshot,
    preferences: AnalysisPreferencesValue
  ) -> [WeightSample] {
    var values = manual.map {
      WeightSample(
        id: $0.id, measuredAt: $0.measuredAt, kilograms: $0.kilograms,
        timeZoneIdentifier: $0.timeZoneIdentifier, source: .manual)
    }
    values += health.samples.compactMap { sample in
      guard sample.type == .bodyMass, let value = sample.value, value.isFinite, value > 0 else {
        return nil
      }
      return .init(
        id: sample.id, measuredAt: sample.start, kilograms: value,
        timeZoneIdentifier: sample.timeZoneIdentifier ?? "UTC", source: sample.source.dataSource)
    }
    return values.map { value in
      var copy = value
      copy.isUserSelected = preferences.weightSelections.contains {
        $0.sampleID == value.id && $0.source == value.source
          && $0.localDate
            == AnalysisFingerprint.localDate(
              value.measuredAt,
              timeZone: TimeZone(identifier: $0.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!)
      }
      return copy
    }.sorted { lhs, rhs in
      lhs.measuredAt == rhs.measuredAt
        ? lhs.id.uuidString < rhs.id.uuidString : lhs.measuredAt < rhs.measuredAt
    }
  }

  static func summary(
    _ snapshot: HealthDataSnapshot, timeZone: TimeZone,
    preferredSources: [String], localWorkouts: [AnalysisWorkout] = []
  ) -> HealthSummary {
    let samples = snapshot.samples.sorted { $0.id.uuidString < $1.id.uuidString }
    var facts = snapshot.activityFacts
    let sleep = samples.filter { $0.type == .sleep && $0.sleepStage?.isAsleep == true }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    // A sleep night is noon-to-noon, labelled by its ending day. Midnight does not split stages.
    let nights = Dictionary(grouping: sleep) {
      AnalysisFingerprint.localDate(
        calendar.date(byAdding: .hour, value: 12, to: $0.end)!, timeZone: timeZone)
    }
    for night in nights.keys.sorted() {
      let all = nights[night]!
      let selected = selectSource(all, preferred: preferredSources)
      guard let first = selected.first else { continue }
      let intervals = selected.map {
        AnalysisWindow(
          start: max($0.start, snapshot.window.start), end: min($0.end, snapshot.window.end))
      }.filter { $0.start < $0.end }
      let duration = unionDuration(intervals)
      var fact = makeFact(
        metric: "sleep.duration", suffix: night, value: duration,
        unit: .seconds, samples: selected, window: snapshot.window)
      fact.sources = [first.source.dataSource]
      if Set(all.map { $0.source.bundleIdentifier }).count > 1 {
        fact.quality.append(.sourceConflict)
      }
      facts.append(fact)
    }
    for type in [HealthDataType.restingHeartRate, .heartRateVariabilitySDNN] {
      let groups = Dictionary(grouping: samples.filter { $0.type == type && $0.value != nil }) {
        sample in
        [
          AnalysisFingerprint.localDate(sample.start, timeZone: timeZone),
          sample.source.bundleIdentifier,
          sample.source.productType ?? "unknown", sample.definition ?? "unknown",
          sample.measurementContext ?? "unspecified",
        ].joined(separator: "|")
      }
      for key in groups.keys.sorted() {
        let group = groups[key]!
        let values = group.compactMap(\.value).filter(\.isFinite)
        guard !values.isEmpty else { continue }
        facts.append(
          makeFact(
            metric: type.rawValue, suffix: key,
            value: values.reduce(0, +) / Double(values.count), unit: group[0].unit,
            samples: group, window: snapshot.window))
      }
    }
    // Local cache fallback uses one source per day and maximum overlapping density, never all-source sums.
    // Fresh snapshots use HealthKit statistics instead (including when statistics return no data).
    if !snapshot.isFresh && snapshot.activityFacts.isEmpty {
      for type in [HealthDataType.steps, .activeEnergy] {
        let groups = Dictionary(grouping: samples.filter { $0.type == type }) {
          AnalysisFingerprint.localDate($0.start, timeZone: timeZone)
        }
        for day in groups.keys.sorted() {
          let chosen = selectSource(groups[day]!, preferred: preferredSources)
          let total = nonOverlappingActivity(chosen)
          var fact = makeFact(
            metric: type.rawValue, suffix: day, value: total,
            unit: type == .steps ? .count : .kilocalories,
            samples: chosen, window: snapshot.window)
          fact.quality = [.estimated]
          if Set(groups[day]!.map { $0.source.bundleIdentifier }).count > 1 {
            fact.quality.append(.sourceConflict)
          }
          facts.append(fact)
        }
      }
    }
    let external = samples.filter { $0.type == .workout }
    let workouts = external.map { sample in
      let duplicates =
        external.filter {
          $0.id != sample.id && $0.workoutActivityCode == sample.workoutActivityCode
            && abs($0.start.timeIntervalSince(sample.start)) <= 300
            && abs($0.end.timeIntervalSince(sample.end)) <= 300
        }.map(\.id)
        + localWorkouts.filter {
          abs($0.startedAt.timeIntervalSince(sample.start)) <= 300
            && abs(($0.endedAt ?? $0.startedAt).timeIntervalSince(sample.end)) <= 300
        }.map(\.id)
      return ExternalWorkoutSummary(
        id: sample.id, start: sample.start, end: sample.end,
        activityCode: sample.workoutActivityCode, source: sample.source.dataSource,
        possibleDuplicateIDs: duplicates.sorted { $0.uuidString < $1.uuidString })
    }
    return .init(
      window: snapshot.window, facts: facts.sorted { $0.id < $1.id },
      externalWorkouts: workouts,
      statuses: snapshot.statuses.sorted { $0.type.rawValue < $1.type.rawValue })
  }

  static func selectSource(_ samples: [HealthSample], preferred: [String]) -> [HealthSample] {
    let sources = Set(samples.map { $0.source.bundleIdentifier }).sorted {
      let a = preferred.firstIndex(of: $0) ?? Int.max
      let b = preferred.firstIndex(of: $1) ?? Int.max
      return a == b ? $0 < $1 : a < b
    }
    guard let source = sources.first else { return [] }
    return samples.filter { $0.source.bundleIdentifier == source }
  }
  static func unionDuration(_ windows: [AnalysisWindow]) -> Double {
    let sorted = windows.sorted { $0.start < $1.start }
    guard var current = sorted.first else { return 0 }
    var total = 0.0
    for interval in sorted.dropFirst() {
      if interval.start <= current.end {
        current.end = max(current.end, interval.end)
      } else {
        total += current.end.timeIntervalSince(current.start)
        current = interval
      }
    }
    return total + current.end.timeIntervalSince(current.start)
  }
  static func nonOverlappingActivity(_ samples: [HealthSample]) -> Double {
    let valid = samples.filter {
      $0.end > $0.start && $0.value.map { $0.isFinite && $0 >= 0 } == true
    }
    let times = Set(valid.flatMap { [$0.start, $0.end] }).sorted()
    guard times.count > 1 else { return 0 }
    return zip(times, times.dropFirst()).reduce(0) { result, interval in
      let density =
        valid.filter { $0.start <= interval.0 && $0.end >= interval.1 }
        .map { $0.value! / $0.end.timeIntervalSince($0.start) }.max() ?? 0
      return result + density * interval.1.timeIntervalSince(interval.0)
    }
  }
  static func makeFact(
    metric: String, suffix: String, value: Double?, unit: MetricUnit,
    samples: [HealthSample], window: AnalysisWindow
  ) -> MetricFact {
    let observedWindow = AnalysisWindow(
      start: max(samples.map(\.start).min() ?? window.start, window.start),
      end: min(samples.map(\.end).max() ?? window.end, window.end))
    return .init(
      id: "health.\(metric).\(suffix)", metric: metric, value: value, unit: unit,
      window: observedWindow,
      sources: Array(Set(samples.map { $0.source.dataSource })).sorted {
        $0.identifier < $1.identifier
      },
      dependencies: samples.map {
        .init(kind: .healthSample, id: $0.id.uuidString, healthType: $0.type)
      }
      .sorted { $0.id < $1.id })
  }
}
