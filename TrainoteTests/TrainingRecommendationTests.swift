import XCTest

@testable import Trainote

final class TrainingRecommendationTests: XCTestCase {
  private let plan = RecommendationPlan(
    id: AnalysisFixtures.id(900), revision: "1", exerciseIDs: ["0025"])
  private var input: AnalysisInput {
    var input = AnalysisFixtures.input(.manualOnly)
    input.workouts = []
    return input
  }
  private func evaluate(
    input: AnalysisInput? = nil, context: TrainingRecommendationContext? = nil,
    score: Double? = 85, state: RecoveryState = .ready, pain: Bool = false,
    systemic: RecoveryState = .unknown
  ) throws -> TrainingRecommendationEvaluation {
    let input = input ?? self.input
    let trend = TrendResult(
      inputFingerprint: input.inputFingerprint, points: [],
      weeklyChangeKilograms: nil, weeklyChangePercent: nil, proposal: nil,
      holdReason: .manualMode, facts: [], calculationVersion: "test-trend")
    let recovery = RecoveryResult(
      inputFingerprint: input.inputFingerprint, asOf: input.asOf,
      muscles: [.init(muscleID: .chest, score: score, state: state, hasPain: pain)],
      systemicState: systemic, systemicFactIDs: [], facts: [], calculationVersion: "test-recovery")
    return try TrainingRecommendationRules(
      context: context
        ?? .init(
          selectedPlan: plan,
          exerciseMuscles: ["0025": [.chest]])
    ).evaluate(input: input, trend: trend, recovery: recovery)
  }

  func testKeepsExplicitPlanAndStableIDsAcrossReevaluation() throws {
    let result = try evaluate()
    XCTAssertEqual(result, try evaluate())
    XCTAssertEqual(result.candidates.map(\.action), [.keepPlan])
    XCTAssertEqual(result.plansByAction[result.candidates[0].id]?.id, plan.id)
    XCTAssertTrue(Set(result.candidates[0].reasonFactIDs).isSubset(of: Set(result.facts.map(\.id))))
    var changed = TrainingRecommendationContext(
      selectedPlan: plan, exerciseMuscles: ["0025": [.chest]])
    changed.selectedPlan?.revision = "2"
    XCTAssertNotEqual(result.candidates[0].id, try evaluate(context: changed).candidates[0].id)
  }
  func testNoPlanNeverClaimsLongTermPlan() throws {
    let result = try evaluate(context: .init(selectedPlan: nil))
    XCTAssertEqual(result.candidates.map(\.action), [.choosePlan])
    XCTAssertTrue(result.candidates[0].exclusionCodes.contains("no_existing_plan"))
    XCTAssertNil(result.facts.first { $0.metric == "recommendation.selectedPlan" }?.value)
  }
  func testPainOverridesHighScoreAndExcludesAffectedPlan() throws {
    let result = try evaluate(score: 100, pain: true)
    XCTAssertEqual(result.candidates.map(\.action), [.rest])
    XCTAssertTrue(result.plansByAction.isEmpty)
  }
  func testTodayPainFeedbackOverridesCalculatorAndFutureFeedbackIsIgnored() throws {
    var input = self.input
    let feedback = MuscleFeedbackValue(
      id: AnalysisFixtures.id(50), muscleID: .chest,
      hasPain: true, recordedAt: input.asOf)
    input.checkIns = [
      .init(
        id: AnalysisFixtures.id(51),
        localDate: AnalysisFingerprint.localDate(
          input.asOf, timeZone: TimeZone(secondsFromGMT: 0)!),
        timeZoneIdentifier: "UTC", muscleFeedback: [feedback], updatedAt: input.asOf)
    ]
    XCTAssertEqual(try evaluate(input: input).candidates.map(\.action), [.rest])
    input.checkIns[0].updatedAt = input.asOf.addingTimeInterval(1)
    XCTAssertEqual(try evaluate(input: input).candidates.map(\.action), [.keepPlan])
  }
  func testUnknownMappingAndReadinessDoNotBecomeFullyReady() throws {
    XCTAssertEqual(
      try evaluate(score: nil, state: .unknown).candidates.map(\.action), [.choosePlan])
    let result = try evaluate(context: .init(selectedPlan: plan))
    XCTAssertEqual(result.candidates.map(\.action), [.choosePlan])
    XCTAssertTrue(result.candidates[0].exclusionCodes.contains("readiness_unknown"))
    XCTAssertNil(result.facts.first { $0.metric == "recommendation.feeling.tired" }?.value)
    XCTAssertNil(result.facts.first { $0.metric == "recommendation.painOrLimitation" }?.value)
  }
  func testUnavailableDayAndSystemicFatiguePreferRest() throws {
    let context = TrainingRecommendationContext(
      selectedPlan: plan,
      availableWeekdays: [], exerciseMuscles: ["0025": [.chest]])
    XCTAssertEqual(
      try evaluate(context: context).candidates.map(\.action), [.rest, .lightActivity])
    XCTAssertEqual(try evaluate(systemic: .limited).candidates.map(\.action), [.rest])
  }
  func testModerateReadinessProducesBoundedOptions() throws {
    let result = try evaluate(score: 60, state: .moderate)
    XCTAssertEqual(result.candidates.map(\.action), [.reduceSets, .increaseRIR])
    XCTAssertEqual(result.candidates[0].allowedParameters[0].minimum, 50)
    XCTAssertEqual(result.candidates[1].allowedParameters[0].maximum, 4)
  }
  func testOnlyCompletedRecentWorkIsCounted() throws {
    var input = AnalysisFixtures.input(.manualOnly)
    input.workouts[0].isCompleted = false
    XCTAssertEqual(try evaluate(input: input).candidates.map(\.action), [.keepPlan])
    input.workouts[0].isCompleted = true
    XCTAssertEqual(
      try evaluate(input: input).candidates.map(\.action), [.reduceSets, .increaseRIR])
    input.workouts[0].exercises[0].sets[0].role = .warmup
    XCTAssertEqual(try evaluate(input: input).candidates.map(\.action), [.keepPlan])
    input.workouts[0].exercises[0].sets[0].role = .working
    input.workouts[0].endedAt = input.asOf.addingTimeInterval(5)
    XCTAssertEqual(try evaluate(input: input).candidates.map(\.action), [.keepPlan])
  }
  func testUnknownNutritionFactFailsClosed() {
    let context = TrainingRecommendationContext(
      selectedPlan: plan, nutritionReviewFactIDs: ["invented"])
    XCTAssertThrowsError(try evaluate(context: context))
  }

  func testPainfulDaySwapsOnlyToKnownReadyUnaffectedTemplate() throws {
    let alternative = RecommendationPlan(
      id: AnalysisFixtures.id(901), revision: "1", exerciseIDs: ["squat"])
    let context = TrainingRecommendationContext(
      selectedPlan: plan, alternativePlans: [alternative],
      exerciseMuscles: ["0025": [.chest], "squat": [.quads]])
    let trend = TrendResult(
      inputFingerprint: input.inputFingerprint, points: [],
      weeklyChangeKilograms: nil, weeklyChangePercent: nil, proposal: nil, holdReason: .manualMode,
      facts: [], calculationVersion: "test")
    var recovery = RecoveryResult(
      inputFingerprint: input.inputFingerprint, asOf: input.asOf,
      muscles: [
        .init(muscleID: .chest, score: 100, state: .ready, hasPain: true),
        .init(muscleID: .quads, score: 85, state: .ready),
      ], systemicState: .unknown,
      systemicFactIDs: [], facts: [], calculationVersion: "test")
    let rules = TrainingRecommendationRules(context: context)
    let result = try rules.evaluate(input: input, trend: trend, recovery: recovery)
    XCTAssertEqual(result.candidates.map(\.action), [.swapTrainingDay, .rest])
    XCTAssertEqual(result.plansByAction[result.candidates[0].id], alternative)
    XCTAssertEqual(result.candidates[0].muscleIDs, [.quads])
    recovery.muscles[1].score = nil
    recovery.muscles[1].state = .unknown
    XCTAssertEqual(
      try rules.candidates(input: input, trend: trend, recovery: recovery).map(\.action), [.rest])
  }

  func testNutritionReviewIsAdditionalAndDoesNotSubtractMuscleReadiness() throws {
    let fact = MetricFact(
      id: "trend.adherence", metric: "adherence", value: 20, unit: .percent,
      window: input.health.window, sources: [.manual])
    let trend = TrendResult(
      inputFingerprint: input.inputFingerprint, points: [],
      weeklyChangeKilograms: nil, weeklyChangePercent: nil, proposal: nil,
      holdReason: .requiresReview,
      facts: [fact], calculationVersion: "test")
    let recovery = RecoveryResult(
      inputFingerprint: input.inputFingerprint, asOf: input.asOf,
      muscles: [.init(muscleID: .chest, score: 90, state: .ready)], systemicState: .unknown,
      systemicFactIDs: [], facts: [], calculationVersion: "test")
    let rules = TrainingRecommendationRules(
      context: .init(
        selectedPlan: plan,
        exerciseMuscles: ["0025": [.chest]], nutritionReviewFactIDs: [fact.id]))
    let result = try rules.evaluate(input: input, trend: trend, recovery: recovery)
    XCTAssertEqual(result.candidates.map(\.action), [.keepPlan, .reviewNutrition])
    XCTAssertTrue(result.candidates.last!.reasonFactIDs.contains(fact.id))
    XCTAssertEqual(recovery.muscles[0].score, 90)
  }
  func testSnapshotBindsFreshCandidateToTemplateAndDoesNotInventMeasuredRIR() throws {
    let routine = Routine(name: "上肢")
    routine.exercises = [
      RoutineExercise(
        sourceExerciseID: "0025", nameEnSnapshot: "Bench",
        nameZhSnapshot: "卧推", orderIndex: 0, trackingMode: .strength, defaultSetCount: 4)
    ]
    let context = TrainingRecommendationContext(
      selectedPlan: .snapshot(routine), exerciseMuscles: ["0025": [.chest]])
    let result = try evaluate(context: context, score: 60, state: .moderate)
    var evaluations = 0
    let reduced = try RecommendationWorkoutFactory.make(
      routine: routine,
      actionID: result.candidates[0].id, parameters: ["retainedSetPercent": 50],
      startedAt: input.asOf
    ) {
      evaluations += 1
      return try self.evaluate(context: context, score: 60, state: .moderate)
    }
    XCTAssertEqual(evaluations, 1)
    XCTAssertEqual(reduced.exercises[0].strengthSets.count, 2)
    XCTAssertEqual(routine.exercises[0].defaultSetCount, 4)
    let easier = try RecommendationWorkoutFactory.make(
      routine: routine,
      actionID: result.candidates[1].id, parameters: ["minimumRIR": 3], startedAt: input.asOf
    ) { result }
    XCTAssertTrue(easier.notes.contains("保留 3 次"))
    XCTAssertTrue(
      easier.exercises.flatMap(\.strengthSets).allSatisfy { !$0.isCompleted && $0.rir == nil })
    XCTAssertThrowsError(
      try RecommendationWorkoutFactory.make(
        routine: routine,
        actionID: result.candidates[0].id, parameters: ["retainedSetPercent": 50],
        startedAt: input.asOf
      ) {
        try self.evaluate(context: context, score: 100, pain: true)
      })
    let otherRoutine = Routine(name: "另一模板")
    otherRoutine.exercises = [
      RoutineExercise(
        sourceExerciseID: "0025", nameEnSnapshot: "Bench",
        nameZhSnapshot: "卧推", orderIndex: 0, trackingMode: .strength, defaultSetCount: 4)
    ]
    XCTAssertThrowsError(
      try RecommendationWorkoutFactory.make(
        routine: otherRoutine,
        actionID: result.candidates[0].id, parameters: ["retainedSetPercent": 50],
        startedAt: input.asOf
      ) { result })
    routine.exercises[0].defaultWeightKilograms = 10
    XCTAssertThrowsError(
      try RecommendationWorkoutFactory.make(
        routine: routine,
        actionID: result.candidates[0].id, parameters: ["retainedSetPercent": 50],
        startedAt: input.asOf
      ) { result })
  }
  func testUnknownLegacySetRoleUsesExplicitVersionedPriorWithoutRewritingIt() throws {
    var input = AnalysisFixtures.input(.manualOnly)
    input.workouts[0].exercises[0].sets[0].role = .unknown
    let result = try evaluate(input: input)
    XCTAssertEqual(result.candidates[0].action, .reduceSets)
    XCTAssertTrue(
      result.facts.first { $0.metric == "recommendation.recentWorkingSets" }!.quality.contains(
        .unknownSetRole))
    XCTAssertEqual(input.workouts[0].exercises[0].sets[0].role, .unknown)
  }
  func testExplicitNoPainHasManualProvenance() throws {
    var input = self.input
    let feedback = MuscleFeedbackValue(
      id: AnalysisFixtures.id(50), muscleID: .chest,
      hasPain: false, hasMovementLimitation: false, recordedAt: input.asOf)
    input.checkIns = [
      .init(
        id: AnalysisFixtures.id(51),
        localDate: AnalysisFingerprint.localDate(
          input.asOf, timeZone: TimeZone(secondsFromGMT: 0)!),
        timeZoneIdentifier: "UTC", muscleFeedback: [feedback], updatedAt: input.asOf)
    ]
    let fact = try evaluate(input: input).facts.first {
      $0.metric == "recommendation.painOrLimitation"
    }!
    XCTAssertEqual(fact.value, 0)
    XCTAssertTrue(
      fact.dependencies.contains(.init(kind: .manualRecord, id: feedback.id.uuidString)))
  }
}
