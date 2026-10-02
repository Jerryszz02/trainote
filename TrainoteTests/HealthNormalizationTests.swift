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
}
