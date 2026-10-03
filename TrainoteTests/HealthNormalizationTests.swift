import XCTest

@testable import Trainote

final class HealthNormalizationTests: XCTestCase {
  func testSleepIntervalsUseUnionIgnoreInBedAndChooseOneSourceAcrossMidnight() throws {
    var snapshot = AnalysisFixtures.health(.duplicateHealthSources)
    let original = snapshot.samples.first { $0.type == .sleep }!
    var overlap = original
    overlap.id = AnalysisFixtures.id(601)
    overlap.start = original.start.addingTimeInterval(3600)
    overlap.end = original.end.addingTimeInterval(-3600)
    overlap.sleepStage = .deep
    snapshot.samples.append(overlap)
    let summary = HealthValueMerge.summary(
      snapshot, timeZone: TimeZone(identifier: "Asia/Shanghai")!,
      preferredSources: [AnalysisFixtures.watch.bundleIdentifier])
    let sleep = try XCTUnwrap(summary.facts.first { $0.metric == "sleep.duration" })
    XCTAssertEqual(sleep.value, 8 * 3600)
    XCTAssertEqual(sleep.sources.map(\.identifier), [AnalysisFixtures.watch.bundleIdentifier])
    XCTAssertEqual(sleep.dependencies.count, 2)
    XCTAssertTrue(sleep.quality.contains(.sourceConflict))
  }
  func testHRVDefinitionsAndSourcesStaySeparateAndExternalWorkoutHasNoLocalSets() {
    var snapshot = AnalysisFixtures.health(.complete)
    var hrv = snapshot.samples.first { $0.type == .heartRateVariabilitySDNN }!
    hrv.id = AnalysisFixtures.id(602)
    hrv.definition = "RMSSD"
    snapshot.samples.append(hrv)
    hrv.id = AnalysisFixtures.id(603)
    hrv.source = AnalysisFixtures.phone
    snapshot.samples.append(hrv)
    let workout = HealthSample(
      id: AnalysisFixtures.id(604), type: .workout,
      start: AnalysisFixtures.asOf.addingTimeInterval(-3600), end: AnalysisFixtures.asOf,
      value: 3600, unit: .seconds, source: AnalysisFixtures.watch, workoutActivityCode: 50)
    var duplicate = workout
    duplicate.id = AnalysisFixtures.id(605)
    duplicate.source = AnalysisFixtures.phone
    snapshot.samples += [workout, duplicate]
    let summary = HealthValueMerge.summary(
      snapshot, timeZone: TimeZone(secondsFromGMT: 0)!, preferredSources: [])
    XCTAssertEqual(summary.facts.filter { $0.metric == "heartRateVariabilitySDNN" }.count, 3)
    XCTAssertEqual(summary.externalWorkouts.count, 2)
    XCTAssertEqual(summary.externalWorkouts.first?.possibleDuplicateIDs.count, 1)
    XCTAssertFalse(summary.facts.contains { $0.metric.contains("sets") })
  }
  func testCachedActivityDoesNotSumOverlappingDevicesAndFreshDoesNotFallbackToRaw() throws {
    var snapshot = AnalysisFixtures.health(.duplicateHealthSources)
    snapshot.isFresh = false
    var step = snapshot.samples.first { $0.type == .steps }!
    step.id = AnalysisFixtures.id(606)
    snapshot.samples.append(step)
    let summary = HealthValueMerge.summary(
      snapshot, timeZone: TimeZone(secondsFromGMT: 0)!,
      preferredSources: [AnalysisFixtures.watch.bundleIdentifier])
    XCTAssertEqual(summary.facts.first { $0.metric == "steps" }?.value, 1000)
    snapshot.isFresh = true
    let fresh = HealthValueMerge.summary(
      snapshot, timeZone: TimeZone(secondsFromGMT: 0)!, preferredSources: [])
    XCTAssertFalse(fresh.facts.contains { $0.metric == "steps" })
  }

  func testSleepCrossingNoonSplitsBeforeUnionAndClipsToQueryWindow() throws {
    let sleep = intervalSample(
      701, type: .sleep, start: "2026-10-03T10:00:00+08:00",
      end: "2026-10-03T14:00:00+08:00", stage: .asleepUnspecified)
    let overlap = intervalSample(
      702, type: .sleep, start: "2026-10-03T10:00:00+08:00",
      end: "2026-10-03T11:00:00+08:00", stage: .deep)
    for (start, end, firstSeconds, secondSeconds) in [
      ("2026-10-03T00:00:00+08:00", "2026-10-05T00:00:00+08:00", 7200.0, 7200.0),
      ("2026-10-03T10:30:00+08:00", "2026-10-03T13:00:00+08:00", 5400.0, 3600.0),
    ] {
      let facts = intervalFacts([sleep, overlap], start: start, end: end, zone: "Asia/Shanghai")
      XCTAssertEqual(
        facts.map(\.id), ["health.sleep.duration.2026-10-03", "health.sleep.duration.2026-10-04"])
      let first = try XCTUnwrap(facts.first)
      let second = try XCTUnwrap(facts.last)
      XCTAssertEqual(first.value, firstSeconds)
      XCTAssertEqual(second.value, secondSeconds)
      XCTAssertEqual(facts.reduce(0) { $0 + ($1.value ?? 0) }, firstSeconds + secondSeconds)
      XCTAssertEqual(first.window.end, instant("2026-10-03T12:00:00+08:00"))
      XCTAssertEqual(second.window.start, first.window.end)
      XCTAssertEqual(
        Set(first.dependencies.map(\.id)), Set([sleep.id.uuidString, overlap.id.uuidString]))
      XCTAssertEqual(second.dependencies.map(\.id), [sleep.id.uuidString])
    }
  }

  func testSleepMidnightStagesRemainInOneNightWithOnePreferredSource() throws {
    let core = intervalSample(
      703, type: .sleep, start: "2026-10-03T23:00:00+08:00",
      end: "2026-10-04T03:00:00+08:00", stage: .core)
    let deep = intervalSample(
      704, type: .sleep, start: "2026-10-04T03:00:00+08:00",
      end: "2026-10-04T07:00:00+08:00", stage: .deep)
    let inBed = intervalSample(
      705, type: .sleep, start: "2026-10-03T22:00:00+08:00",
      end: "2026-10-04T09:00:00+08:00", stage: .inBed)
    var otherSource = intervalSample(
      706, type: .sleep, start: "2026-10-03T23:00:00+08:00",
      end: "2026-10-04T08:00:00+08:00", stage: .asleepUnspecified)
    otherSource.source = AnalysisFixtures.phone
    let facts = intervalFacts(
      [core, deep, inBed, otherSource], start: "2026-10-03T22:00:00+08:00",
      end: "2026-10-04T10:00:00+08:00", zone: "Asia/Shanghai")
    XCTAssertEqual(facts.count, 1)
    let fact = try XCTUnwrap(facts.first)
    XCTAssertEqual(fact.id, "health.sleep.duration.2026-10-04")
    XCTAssertEqual(fact.value, 8 * 3600)
    XCTAssertEqual(Set(fact.dependencies.map(\.id)), Set([core.id.uuidString, deep.id.uuidString]))
    XCTAssertTrue(fact.quality.contains(.sourceConflict))
  }

  func testSleepNoonBoundariesFollowCalendarAcrossSpringAndFallDST() throws {
    for (start, end, days, middleHours) in [
      (
        "2026-03-07T11:00:00-08:00", "2026-03-08T13:00:00-07:00",
        ["2026-03-07", "2026-03-08", "2026-03-09"], 23.0
      ),
      (
        "2026-10-31T11:00:00-07:00", "2026-11-01T13:00:00-08:00",
        ["2026-10-31", "2026-11-01", "2026-11-02"], 25.0
      ),
    ] {
      let sample = intervalSample(707, type: .sleep, start: start, end: end, stage: .core)
      let facts = intervalFacts([sample], start: start, end: end, zone: "America/Los_Angeles")
      XCTAssertEqual(facts.map(\.id), days.map { "health.sleep.duration." + $0 })
      XCTAssertEqual(facts.map(\.value), [3600, middleHours * 3600, 3600])
      XCTAssertEqual(
        facts.reduce(0) { $0 + ($1.value ?? 0) }, sample.end.timeIntervalSince(sample.start))
      XCTAssertTrue(facts.allSatisfy { $0.dependencies.map(\.id) == [sample.id.uuidString] })
    }
  }

  func testSleepUsesAnalysisTimezoneNoonIncludingFractionalOffsets() {
    let start = "2026-10-03T05:15:00Z"
    let end = "2026-10-03T07:15:00Z"
    let sample = intervalSample(708, type: .sleep, start: start, end: end, stage: .core)
    let local = intervalFacts([sample], start: start, end: end, zone: "Asia/Kathmandu")
    XCTAssertEqual(
      local.map(\.id), ["health.sleep.duration.2026-10-03", "health.sleep.duration.2026-10-04"])
    XCTAssertEqual(local.map(\.value), [3600, 3600])
    let utc = intervalFacts([sample], start: start, end: end, zone: "UTC")
    XCTAssertEqual(utc.map(\.id), ["health.sleep.duration.2026-10-03"])
    XCTAssertEqual(utc.map(\.value), [7200])
  }

  func testCachedActivityClipsQuantityToWindowAndIgnoresDisjointSamples() throws {
    let sample = intervalSample(
      709, type: .activeEnergy, start: "2026-10-03T09:00:00Z",
      end: "2026-10-03T12:00:00Z", value: 300)
    let facts = intervalFacts(
      [sample], start: "2026-10-03T10:00:00Z",
      end: "2026-10-03T11:00:00Z", zone: "UTC")
    XCTAssertEqual(facts.count, 1)
    let fact = try XCTUnwrap(facts.first)
    XCTAssertEqual(fact.value, 100)
    XCTAssertEqual(
      fact.window,
      .init(start: instant("2026-10-03T10:00:00Z"), end: instant("2026-10-03T11:00:00Z")))
    XCTAssertEqual(fact.dependencies.map(\.id), [sample.id.uuidString])
    XCTAssertTrue(fact.quality.contains(.estimated))
    XCTAssertTrue(
      intervalFacts(
        [sample], start: "2026-10-03T12:00:00Z",
        end: "2026-10-03T13:00:00Z", zone: "UTC"
      ).isEmpty)
  }

  func testCachedActivitySplitsDaysBeforeDeduplicatingOverlapsAndSources() throws {
    let sample = intervalSample(
      710, type: .activeEnergy, start: "2026-10-03T23:00:00+08:00",
      end: "2026-10-04T02:00:00+08:00", value: 300)
    let overlap = intervalSample(
      711, type: .activeEnergy, start: "2026-10-04T00:00:00+08:00",
      end: "2026-10-04T01:00:00+08:00", value: 100)
    var otherSource = sample
    otherSource.id = AnalysisFixtures.id(712)
    otherSource.source = AnalysisFixtures.phone
    otherSource.value = 900
    let facts = intervalFacts(
      [sample, overlap, otherSource], start: "2026-10-03T23:30:00+08:00",
      end: "2026-10-04T01:00:00+08:00", zone: "Asia/Shanghai")
    XCTAssertEqual(
      facts.map(\.id), ["health.activeEnergy.2026-10-03", "health.activeEnergy.2026-10-04"])
    XCTAssertEqual(facts.map(\.value), [50, 100])
    let first = try XCTUnwrap(facts.first)
    let last = try XCTUnwrap(facts.last)
    XCTAssertEqual(first.window.end, instant("2026-10-04T00:00:00+08:00"))
    XCTAssertEqual(last.window.start, first.window.end)
    XCTAssertEqual(first.dependencies.map(\.id), [sample.id.uuidString])
    XCTAssertEqual(
      Set(last.dependencies.map(\.id)), Set([sample.id.uuidString, overlap.id.uuidString]))
    XCTAssertTrue(
      facts.allSatisfy { $0.quality.contains(.sourceConflict) && $0.quality.contains(.estimated) })
    XCTAssertTrue(
      facts.allSatisfy { $0.sources.map(\.identifier) == [AnalysisFixtures.watch.bundleIdentifier] }
    )
  }

  func testCachedActivityUsesActualDSTDayLengthAndLocalMidnight() throws {
    for (start, end, queryStart, queryEnd, day, quantity, expected) in [
      (
        "2026-03-07T12:00:00-08:00", "2026-03-09T12:00:00-07:00", "2026-03-08T00:00:00-08:00",
        "2026-03-09T00:00:00-07:00", "2026-03-08", 4700.0, 2300.0
      ),
      (
        "2026-10-31T12:00:00-07:00", "2026-11-02T12:00:00-08:00", "2026-11-01T00:00:00-07:00",
        "2026-11-02T00:00:00-08:00", "2026-11-01", 4900.0, 2500.0
      ),
    ] {
      let sample = intervalSample(713, type: .steps, start: start, end: end, value: quantity)
      let facts = intervalFacts(
        [sample], start: queryStart, end: queryEnd, zone: "America/Los_Angeles")
      XCTAssertEqual(facts.map(\.id), ["health.steps." + day])
      XCTAssertEqual(facts.map(\.value), [expected])
      XCTAssertEqual(facts.first?.window, .init(start: instant(queryStart), end: instant(queryEnd)))
    }
    let sample = intervalSample(
      714, type: .steps, start: "2026-10-03T18:00:00Z",
      end: "2026-10-03T20:00:00Z", value: 200)
    let facts = intervalFacts(
      [sample], start: "2026-10-03T18:00:00Z", end: "2026-10-03T20:00:00Z", zone: "Asia/Kathmandu")
    XCTAssertEqual(facts.map(\.id), ["health.steps.2026-10-03", "health.steps.2026-10-04"])
    XCTAssertEqual(facts.map(\.value), [25, 175])
  }

  private func instant(_ string: String) -> Date {
    ISO8601DateFormatter().date(from: string)!
  }

  private func intervalSample(
    _ id: Int, type: HealthDataType, start: String, end: String,
    value: Double? = nil, stage: SleepStage? = nil
  ) -> HealthSample {
    .init(
      id: AnalysisFixtures.id(id), type: type, start: instant(start), end: instant(end),
      value: value, unit: type == .sleep ? .seconds : (type == .steps ? .count : .kilocalories),
      source: AnalysisFixtures.watch, timeZoneIdentifier: "UTC", sleepStage: stage)
  }

  private func intervalFacts(_ samples: [HealthSample], start: String, end: String, zone: String)
    -> [MetricFact]
  {
    let snapshot = HealthDataSnapshot(
      window: .init(start: instant(start), end: instant(end)),
      fetchedAt: instant(end), isFresh: false, samples: samples, statuses: [])
    return HealthValueMerge.summary(
      snapshot, timeZone: TimeZone(identifier: zone)!,
      preferredSources: [AnalysisFixtures.watch.bundleIdentifier]
    ).facts
  }

}
