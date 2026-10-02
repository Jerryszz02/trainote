import XCTest

@testable import Trainote

final class RecoveryCalculatorTests: XCTestCase {
  let now = Date(timeIntervalSince1970: 1_790_985_600)
  func calculator() throws -> RecoveryCalculator { .init(mapping: try .load()) }
  func input(_ workouts: [AnalysisWorkout] = []) -> AnalysisInput {
    .init(
      asOf: now, calendarTimeZone: "UTC", inputFingerprint: "synthetic",
      workouts: workouts,
      health: .empty(window: .init(start: now.addingTimeInterval(-90 * 86_400), end: now)))
  }
  func workout(
    id: String = "0025", hoursAgo: Double = 0, count: Int = 1,
    rir: Int? = 3, role: SetRole = .working
  ) -> AnalysisWorkout {
    .init(
      id: UUID(), startedAt: now.addingTimeInterval(-hoursAgo * 3600 - 3600),
      endedAt: now.addingTimeInterval(-hoursAgo * 3600), isCompleted: true,
      exercises: [
        .init(
          id: UUID(), sourceExerciseID: id, trackingMode: "strength",
          sets: (0..<count).map {
            .init(
              id: UUID(), orderIndex: $0, weightKilograms: 60,
              repetitions: 8, durationSeconds: 0, isCompleted: true, rir: rir, role: role)
          })
      ])
  }
  func chest(_ result: RecoveryResult) throws -> MuscleRecovery {
    try XCTUnwrap(result.muscles.first { $0.muscleID == .chest })
  }

  func testAll1324CatalogIDsHaveExplicitSupportAndElevenMuscleIDs() throws {
    let mapping = try ExerciseMuscleMap.load()
    let url = try XCTUnwrap(Bundle.main.url(forResource: "ExerciseCatalog", withExtension: "json"))
    let catalog = try JSONDecoder().decode(
      ExerciseCatalogDocument.self, from: Data(contentsOf: url))
    XCTAssertEqual(Set(mapping.entries.map(\.exerciseID)), Set(catalog.exercises.map(\.id)))
    XCTAssertEqual(mapping.entries.filter { $0.status == .mapped }.count, 38)
    XCTAssertEqual(mapping.byID["0025"]?.weights, [.chest: 1, .triceps: 0.5, .shoulders: 0.5])
    XCTAssertEqual(
      Set(mapping.entries.flatMap { $0.primary + $0.secondary }), Set(MuscleID.allCases))
    let duplicate = ExerciseMuscleMap.Entry(
      exerciseID: "test", status: .mapped,
      primary: [.chest, .chest], secondary: [.chest, .triceps, .triceps], reason: "test")
    XCTAssertEqual(duplicate.weights, [.chest: 1, .triceps: 0.5])
  }
  func testOnlyCompletedWorkingSetsInCompletedWorkoutCount() throws {
    let valid = workout()
    var active = workout(count: 20)
    active.isCompleted = false
    var planned = workout(count: 20)
    planned.exercises[0].sets[0].isCompleted = false
    planned.exercises[0].sets = [planned.exercises[0].sets[0]]
    let warmup = workout(count: 20, role: .warmup)
    let result = try calculator().calculate(input([valid, active, planned, warmup]))
    XCTAssertEqual(try XCTUnwrap(chest(result).score), 100 * exp(-1 / 6), accuracy: 0.0001)
    XCTAssertNil(result.muscles.first { $0.muscleID == .quads }?.score)
  }
  func testEachRIRWeightAndUnknownRolePrior() throws {
    for rir in 0...5 {
      let result = try calculator().calculate(input([workout(rir: rir)]))
      XCTAssertEqual(
        try XCTUnwrap(chest(result).score), 100 * exp(-RecoveryParameters.effortWeights[rir] / 6),
        accuracy: 0.0001)
    }
    let result = try calculator().calculate(input([workout(rir: nil, role: .unknown)]))
    XCTAssertEqual(try XCTUnwrap(chest(result).score), 100 * exp(-1 / 6), accuracy: 0.0001)
    XCTAssertTrue(try chest(result).coverage[0].quality.contains(.unknownRIR))
    XCTAssertTrue(try chest(result).coverage[0].quality.contains(.unknownSetRole))
  }
  func testMissingUnreviewedUnknownAndUnsupportedModesStayUnknown() throws {
    for workouts in [
      [], [workout(id: "not-an-exercise")], [workout(id: "0001")],
      [workout(), workout(id: "not-an-exercise")],
    ] {
      let result = try calculator().calculate(input(workouts))
      XCTAssertTrue(result.muscles.allSatisfy { $0.score == nil })
    }
    var timed = workout()
    timed.exercises[0].trackingMode = "duration"
    timed.exercises[0].sets[0].durationSeconds = 60
    XCTAssertNil(try chest(calculator().calculate(input([timed]))).score)
    var external = input()
    external.health.externalWorkouts = [
      .init(
        id: UUID(), start: now.addingTimeInterval(-3600), end: now,
        activityCode: 50, source: .init(kind: .healthKit, identifier: "synthetic"),
        possibleDuplicateIDs: [])
    ]
    let result = try calculator().calculate(external)
    XCTAssertTrue(result.muscles.allSatisfy { $0.score == nil })
    XCTAssertEqual(result.facts.first { $0.id == "recovery.systemic.externalWorkout" }?.value, 3600)
  }
  func testDecayIsDeterministicMonotonicAndEditDeleteRecalculate() throws {
    var value = input([workout(hoursAgo: 2, count: 5)])
    let c = try calculator()
    let before = try c.calculate(value)
    XCTAssertEqual(before, try c.calculate(value))
    value.asOf.addTimeInterval(12 * 3600)
    XCTAssertGreaterThan(
      try XCTUnwrap(chest(c.calculate(value)).score), try XCTUnwrap(chest(before).score))
    value.workouts[0].exercises[0].sets.removeLast()
    let changed = try c.calculate(value)
    XCTAssertGreaterThan(try XCTUnwrap(chest(changed).score), try XCTUnwrap(chest(before).score))
    value.workouts = []
    XCTAssertNil(try chest(c.calculate(value)).score)
  }
  func testInvalidAndFutureTrainingAreNotLoadAndMissingEndHasQuality() throws {
    var future = workout()
    future.endedAt = now.addingTimeInterval(3600)
    var reversed = workout()
    reversed.endedAt = reversed.startedAt.addingTimeInterval(-1)
    var bad = workout()
    bad.exercises[0].sets[0].weightKilograms = .nan
    for item in [future, reversed, bad] {
      XCTAssertNil(try chest(calculator().calculate(input([item]))).score)
    }
    var fallback = workout()
    fallback.endedAt = nil
    XCTAssertNotNil(try chest(calculator().calculate(input([fallback]))).score)
    XCTAssertTrue(
      try chest(calculator().calculate(input([fallback]))).coverage[0].quality.contains(.estimated))
  }
  func testFeedbackDoesNotFabricateScoreAndPainOverridesHighScoreUntilCleared() throws {
    var value = input([workout(hoursAgo: 96)])
    let response = MuscleFeedbackValue(
      id: UUID(), muscleID: .chest, soreness: .significant,
      hasPain: true, hasMovementLimitation: true, recordedAt: now.addingTimeInterval(-86_400))
    value.checkIns = [
      .init(
        id: UUID(),
        localDate: AnalysisFingerprint.localDate(now.addingTimeInterval(-86_400), timeZone: .gmt),
        timeZoneIdentifier: "GMT", muscleFeedback: [response], updatedAt: response.recordedAt)
    ]
    let result = try calculator().calculate(value)
    let muscle = try chest(result)
    XCTAssertGreaterThan(try XCTUnwrap(muscle.score), 95)
    XCTAssertEqual(muscle.state, .limited)
    XCTAssertTrue(
      result.bodyMapPresentation(selected: .chest).muscles.first { $0.muscleID == .chest }!.hasPain)
    var clear = response
    clear.id = UUID()
    clear.recordedAt = now
    clear.hasPain = false
    clear.hasMovementLimitation = false
    value.checkIns.append(
      .init(
        id: UUID(), localDate: AnalysisFingerprint.localDate(now, timeZone: .gmt),
        timeZoneIdentifier: "GMT", muscleFeedback: [clear], updatedAt: now))
    XCTAssertEqual(try chest(calculator().calculate(value)).state, .moderate)
    value.workouts = []
    XCTAssertNil(try chest(calculator().calculate(value)).score)
  }
  func testEveryFactDependencyCanBeResolvedAndLocalScoreDoesNotDependOnHRV() throws {
    var value = input([workout(rir: nil)])
    let base = try calculator().calculate(value)
    value.health.facts = [
      .init(
        id: "health.unknown", metric: "heartRateVariabilitySDNN", value: 1, unit: .milliseconds,
        window: .init(start: now, end: now), sources: [.init(kind: .healthKit, identifier: "test")],
        dependencies: [
          .init(kind: .healthSample, id: UUID().uuidString, healthType: .heartRateVariabilitySDNN)
        ])
    ]
    let after = try calculator().calculate(value)
    XCTAssertEqual(base.muscles, after.muscles)
    let ids = Set(after.facts.map(\.id) + value.health.facts.map(\.id))
    XCTAssertEqual(after.facts.count, Set(after.facts.map(\.id)).count)
    for fact in after.facts {
      for dependency in fact.dependencies where dependency.kind == .metricFact {
        XCTAssertTrue(ids.contains(dependency.id))
      }
    }
    XCTAssertTrue(
      after.facts.filter { $0.metric == "recovery.residualLoad" }.allSatisfy {
        !$0.dependencies.contains { $0.kind == .healthSample }
      })
  }
}
