import XCTest

@testable import Trainote

final class RecoveryCalibrationTests: XCTestCase {
  let start = Date(timeIntervalSince1970: 1_785_801_600)
  func observations(count: Int, targetTau: Double) -> [RecoveryCalibration.Observation] {
    (0..<count).map { index in
      let date = start.addingTimeInterval(Double(index) * 8 * 86_400)
      let load = RecoveryLoadSession(
        workoutID: UUID(), endedAt: date.addingTimeInterval(-36 * 3600),
        load: [.chest: 8], quality: [],
        dependencies: [.init(kind: .manualRecord, id: "load-\(index)")])
      var value = RecoveryCalibration.Observation(
        workoutID: UUID(), date: date,
        observedPerformance: 0, priorLoads: [load],
        dependencies: [.init(kind: .manualRecord, id: "pair-\(index)")])
      value.observedPerformance = RecoveryCalibration.prediction(
        value, tau: targetTau, muscle: .chest)
      return value
    }
  }
  func testSixTrainingAndFourDistinctTemporalHoldoutSamplesAreRequired() {
    let rows = observations(count: 10, targetTau: 24)
    let insufficient = RecoveryCalibration.fit(
      Array(rows.prefix(9)), muscle: .chest, asOf: rows.last!.date)
    XCTAssertFalse(insufficient.isAdopted)
    let candidate = RecoveryCalibration.fit(rows, muscle: .chest, asOf: rows.last!.date)
    XCTAssertTrue(candidate.isAdopted)
    XCTAssertEqual(candidate.trainingCount, 6)
    XCTAssertEqual(candidate.holdoutCount, 4)
    XCTAssertEqual(candidate.tauHours, 32.4, accuracy: 0.0001)
    XCTAssertLessThan(candidate.candidateError!, candidate.baselineError!)
    XCTAssertTrue(candidate.dependencies.contains { $0.id == "load-0" })
  }
  func testFitImprovementWithoutHoldoutImprovementIsRejected() {
    var rows = observations(count: 10, targetTau: 24)
    for index in 6..<10 {
      rows[index].observedPerformance = RecoveryCalibration.prediction(
        rows[index], tau: 72, muscle: .chest)
    }
    let result = RecoveryCalibration.fit(rows, muscle: .chest, asOf: rows.last!.date)
    XCTAssertFalse(result.isAdopted)
    XCTAssertEqual(result.tauHours, 36)
  }
  func testNoWeeklyRepeatAndBoundedTenPercentSteps() {
    var rows = observations(count: 40, targetTau: 24)
    let first = RecoveryCalibration.fit(Array(rows.prefix(10)), muscle: .chest, asOf: rows[9].date)
    rows[10].date = rows[9].date.addingTimeInterval(86_400)
    let tomorrow = RecoveryCalibration.fit(
      Array(rows.prefix(11)), muscle: .chest, asOf: rows[10].date)
    XCTAssertEqual(first.tauHours, tomorrow.tauHours)
    let longTerm = RecoveryCalibration.fit(rows, muscle: .chest, asOf: rows.last!.date)
    XCTAssertGreaterThanOrEqual(longTerm.tauHours, 24)
    XCTAssertLessThanOrEqual(longTerm.tauHours, 72)
    XCTAssertGreaterThanOrEqual(longTerm.tauHours, first.tauHours * pow(0.9, 30))
  }
  func testEqualDatesCannotPretendToBeIndependentTimeHoldout() {
    var rows = observations(count: 10, targetTau: 24)
    for index in rows.indices { rows[index].date = start }
    XCTAssertFalse(RecoveryCalibration.fit(rows, muscle: .chest, asOf: start).isAdopted)
  }
  func testResetAndChangedExerciseOrRIRCannotReuseLearnedState() throws {
    let helper = RecoveryCalculatorTests()
    var input = helper.input()
    input.workouts = (0..<15).map { index in
      var workout = helper.workout(hoursAgo: Double(15 - index) * 48, rir: 2)
      workout.exercises[0].sets[0].orderIndex = 0
      return workout
    }
    input.checkIns = input.workouts.map { workout in
      let date = workout.startedAt.addingTimeInterval(-600)
      return .init(
        id: UUID(), localDate: AnalysisFingerprint.localDate(date, timeZone: .gmt),
        timeZoneIdentifier: "GMT", feeling: .normal,
        muscleFeedback: [
          .init(
            id: UUID(), muscleID: .chest, soreness: SorenessLevel.none,
            hasPain: false, hasMovementLimitation: false, recordedAt: date)
        ], updatedAt: date)
    }
    let calc = try helper.calculator()
    let sessions = calc.extract(input).sessions
    let observations = RecoveryCalibration.observations(
      input: input, sessions: sessions, mapping: calc.mapping, resetAt: nil)
    XCTAssertEqual(observations[.chest]?.count, 12)
    let reset = RecoveryCalibration.observations(
      input: input, sessions: sessions, mapping: calc.mapping, resetAt: input.asOf)
    XCTAssertTrue(reset.isEmpty)
    for index in input.workouts.indices { input.workouts[index].exercises[0].sets[0].rir = nil }
    let noEffort = RecoveryCalibration.observations(
      input: input, sessions: sessions, mapping: calc.mapping, resetAt: nil)
    XCTAssertTrue(noEffort.isEmpty)
    let defaults = UserDefaults(suiteName: "recovery-tests-\(UUID())")!
    let control = RecoveryCalibrationControl(defaults: defaults)
    control.reset(at: input.asOf)
    XCTAssertEqual(control.resetAt, input.asOf)
    control.clear()
    XCTAssertNil(control.resetAt)
  }
}
