import Foundation

struct TrendWeightDay {
  var date: Date
  var value: Double
  var samples: [WeightSample]
  var quality: [DataQualityFlag]
  var isUsable: Bool
  var wasExplicitlySelected: Bool
  var dependencies: [SourceDependency] {
    samples.map {
      .init(
        kind: $0.source.kind == .healthKit ? .healthSample : .manualRecord,
        id: $0.id.uuidString, healthType: $0.source.kind == .healthKit ? .bodyMass : nil)
    }
  }
}

enum TrendWeightSeries {
  static func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let values = values.sorted()
    let middle = values.count / 2
    return values.count.isMultiple(of: 2)
      ? (values[middle - 1] + values[middle]) / 2 : values[middle]
  }

  static func days(input: AnalysisInput, calendar: TrendCalendar, rules: TrendRules) throws
    -> [TrendWeightDay]
  {
    var byID: [UUID: WeightSample] = [:]
    for sample in input.weights {
      guard sample.source.kind != .calculation, !sample.source.identifier.isEmpty,
        TimeZone(identifier: sample.timeZoneIdentifier) != nil
      else {
        throw AnalysisFailure.invalidInput
      }
      if let previous = byID[sample.id], previous != sample { throw AnalysisFailure.invalidInput }
      byID[sample.id] = sample
    }
    let grouped = Dictionary(
      grouping: byID.values.filter {
        $0.measuredAt <= input.asOf && $0.measuredAt.timeIntervalSince1970.isFinite
          && $0.kilograms.isFinite && $0.kilograms > 0
      }
    ) { calendar.key($0.measuredAt) }
    var result: [TrendWeightDay] = grouped.keys.sorted().compactMap { key in
      guard let all = grouped[key] else { return nil }
      let ordered = all.sorted {
        $0.measuredAt == $1.measuredAt
          ? $0.id.uuidString < $1.id.uuidString
          : $0.measuredAt < $1.measuredAt
      }
      // Selections are references. Never copy a HealthKit value into manual persistence.
      let explicit = ordered.filter { sample in
        sample.isUserSelected
          || input.preferences.weightSelections.contains {
            $0.sampleID == sample.id && $0.source == sample.source
              && $0.localDate == key && calendar.matches($0.timeZoneIdentifier)
          }
      }
      let sources = Set(ordered.map { $0.source.identifier })
      let preferred = input.preferences.preferredWeightSourceID
      let source =
        preferred.flatMap { sources.contains($0) ? $0 : nil }
        ?? (sources.contains(DataSource.manual.identifier)
          ? DataSource.manual.identifier : sources.sorted().first!)
      let sameSource = ordered.filter { $0.source.identifier == source }
      let morning = sameSource.filter {
        rules.morningHours.contains(calendar.calendar.component(.hour, from: $0.measuredAt))
      }
      let selected: [WeightSample]
      if let sample = explicit.last {
        selected = [sample]
      } else if let sample = morning.first {
        selected = [sample]
      } else {
        selected = sameSource
      }
      guard let value = median(selected.map(\.kilograms)),
        let time = median(selected.map { $0.measuredAt.timeIntervalSince1970 })
      else { return nil }
      return .init(
        date: Date(timeIntervalSince1970: time), value: value, samples: selected,
        quality: sources.count > 1 ? [.sourceConflict] : [],
        isUsable: rules.admissibleWeight.contains(value), wasExplicitlySelected: !explicit.isEmpty)
    }
    // Local robust screen: preserves the raw point and dependency, but excludes it from the fit.
    // An explicit representative overrides the statistical screen, never the admissible range.
    for index in result.indices {
      let nearby = result.filter {
        abs($0.date.timeIntervalSince(result[index].date)) <= rules.outlierNeighbourDays * 86_400
          && $0.isUsable
      }
      if nearby.count >= rules.minimumOutlierNeighbours, let center = median(nearby.map(\.value)),
        let mad = median(nearby.map { abs($0.value - center) }),
        abs(result[index].value - center)
          > max(rules.minimumOutlierDistance, rules.outlierMADMultiplier * mad),
        !result[index].wasExplicitlySelected
      {
        result[index].isUsable = false
      }
      if !result[index].isUsable { result[index].quality.append(.requiresReview) }
    }
    return result
  }

  static func points(days: [TrendWeightDay], rules: TrendRules) -> [TrendPoint] {
    var previous: (Date, Double)?
    return days.map { day in
      var smooth: Double?
      if day.isUsable {
        if let (date, value) = previous {
          let alpha = 1 - exp(-day.date.timeIntervalSince(date) / (rules.smoothingDays * 86_400))
          smooth = value + alpha * (day.value - value)
        } else {
          smooth = day.value
        }
        previous = (day.date, smooth!)
      }
      return .init(
        date: day.date, observedKilograms: day.value,
        smoothedKilograms: smooth, sampleIDs: day.samples.map(\.id))
    }
  }
  static func weeklySlope(_ days: [TrendWeightDay]) -> Double? {
    var slopes: [Double] = []
    for (i, first) in days.enumerated() {
      for second in days.dropFirst(i + 1) {
        let elapsedDays = second.date.timeIntervalSince(first.date) / 86_400
        if elapsedDays > 0 { slopes.append((second.value - first.value) / elapsedDays * 7) }
      }
    }
    return median(slopes)
  }
}
