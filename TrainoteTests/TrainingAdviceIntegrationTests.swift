import SwiftData
import XCTest

@testable import Trainote

@MainActor
final class TrainingAdviceIntegrationTests: XCTestCase {
  private let baseTime = AnalysisFixtures.asOf
  private final class Clock {
    var value: Date
    init(_ value: Date) { self.value = value }
  }

  private func setup(
    mode: TrackingMode = .strength, withCoverageGap: Bool = false,
    historyAgeHours: Double = 48
  ) throws
    -> (TrainingAdviceController, SwiftDataAnalysisRepository, ModelContext, Routine, Clock)
  {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let repository = SwiftDataAnalysisRepository(container: container)
    let context = ModelContext(container)
    let routine = Routine(name: "上肢模板")
    routine.exercises = [
      RoutineExercise(
        sourceExerciseID: "0025", nameEnSnapshot: "Bench", nameZhSnapshot: "卧推",
        orderIndex: 0, trackingMode: mode, defaultSetCount: 4)
    ]
    context.insert(routine)
    let history = Workout(
      title: "原有训练", startedAt: baseTime.addingTimeInterval(-(historyAgeHours + 1) * 3600),
      endedAt: baseTime.addingTimeInterval(-historyAgeHours * 3600), status: .completed)
    let exercise = WorkoutExercise(
      sourceExerciseID: "0025", nameEnSnapshot: "Bench", nameZhSnapshot: "卧推",
      orderIndex: 0, trackingMode: .strength)
    let set = StrengthSet(
      orderIndex: 0, weightKilograms: 60, repetitions: 8,
      isCompleted: true, rir: 2, setRole: .working)
    set.exercise = exercise
    exercise.strengthSets = [set]
    exercise.workout = history
    history.exercises = [exercise]
    context.insert(history)
    if withCoverageGap {
      let gap = Workout(
        title: "未审核动作", startedAt: baseTime.addingTimeInterval(-47 * 3600),
        endedAt: baseTime.addingTimeInterval(-46 * 3600), status: .completed)
      let gapExercise = WorkoutExercise(
        sourceExerciseID: "unreviewed", nameEnSnapshot: "Unknown", nameZhSnapshot: "未知",
        orderIndex: 0, trackingMode: .strength)
      let gapSet = StrengthSet(
        orderIndex: 0, weightKilograms: 20, repetitions: 8,
        isCompleted: true, rir: 2, setRole: .working)
      gapSet.exercise = gapExercise
      gapExercise.strengthSets = [gapSet]
      gapExercise.workout = gap
      gap.exercises = [gapExercise]
      context.insert(gap)
    }
    try context.save()
    let clock = Clock(baseTime)
    let controller = TrainingAdviceController(
      repository: repository, healthData: nil, recovery: try RecoveryService(),
      modelContext: context, now: { clock.value }, timeZone: { .gmt })
    controller.loadRoutines()
    controller.selectedRoutineID = routine.id
    controller.refresh()
    return (controller, repository, context, routine, clock)
  }

  func testClockChangeStillAdoptsFreshApprovedActionAndPersistsNewSnapshot() throws {
    let (controller, _, context, routine, clock) = try setup()
    let candidate = try XCTUnwrap(
      controller.evaluation?.candidates.first { $0.action == .keepPlan })
    clock.value = baseTime.addingTimeInterval(2)
    let workout = try controller.adopt(actionID: candidate.id)
    XCTAssertEqual(workout.status, .inProgress)
    XCTAssertNotEqual(
      workout.id,
      try XCTUnwrap(
        context.fetch(FetchDescriptor<Workout>())
          .first { $0.status == .completed }
      ).id)
    XCTAssertTrue(
      workout.exercises.flatMap(\.strengthSets).allSatisfy {
        !$0.isCompleted && $0.rir == nil && $0.setRole == .working
      })
    XCTAssertEqual(routine.exercises[0].defaultSetCount, 4)
    XCTAssertEqual(try context.fetch(FetchDescriptor<Workout>()).count, 2)
  }

  func testExistingWorkoutIsShownBeforeAdoptionAndStillBlocksDuplicateCreation() throws {
    let (controller, _, context, _, _) = try setup()
    let candidate = try XCTUnwrap(
      controller.evaluation?.candidates.first { $0.action == .keepPlan })
    let active = Workout(title: "进行中", startedAt: baseTime, status: .inProgress)
    context.insert(active)
    try context.save()
    controller.loadRoutines()
    XCTAssertEqual(controller.activeWorkout?.id, active.id)
    XCTAssertThrowsError(try controller.adopt(actionID: candidate.id)) {
      guard case TrainingAdviceAdoptionError.inProgressWorkout = $0 else {
        return XCTFail("Expected the specific in-progress conflict")
      }
    }
    XCTAssertEqual(try context.fetch(FetchDescriptor<Workout>()).count, 2)
  }

  func testTemplateEditAndRecordEditHaveDifferentAdoptionErrors() throws {
    let (templateController, _, templateContext, routine, _) = try setup()
    let templateCandidate = try XCTUnwrap(
      templateController.evaluation?.candidates.first { $0.action == .keepPlan })
    routine.exercises[0].defaultWeightKilograms = 10
    try templateContext.save()
    XCTAssertThrowsError(try templateController.adopt(actionID: templateCandidate.id)) {
      guard case TrainingAdviceAdoptionError.templateChanged = $0 else {
        return XCTFail("Expected a template change")
      }
    }
    let (recordController, repository, _, _, _) = try setup()
    let recordCandidate = try XCTUnwrap(
      recordController.evaluation?.candidates.first { $0.action == .keepPlan })
    var profile = try XCTUnwrap(AnalysisFixtures.input(.manualOnly).profile)
    profile.updatedAt = baseTime
    try repository.saveProfile(profile)
    XCTAssertThrowsError(try recordController.adopt(actionID: recordCandidate.id)) {
      guard case TrainingAdviceAdoptionError.recordsChanged = $0 else {
        return XCTFail("Expected a record change")
      }
    }
  }

  func testNewPainRejectsDisplayedActionBeforeSaving() throws {
    let (controller, repository, context, _, _) = try setup()
    let candidate = try XCTUnwrap(
      controller.evaluation?.candidates.first { $0.action == .keepPlan })
    let feedback = MuscleFeedbackValue(
      id: UUID(), muscleID: .chest, hasPain: true, recordedAt: baseTime)
    try repository.saveCheckIn(
      .init(
        id: UUID(), localDate: AnalysisFingerprint.localDate(baseTime, timeZone: .gmt),
        timeZoneIdentifier: TimeZone.gmt.identifier,
        muscleFeedback: [feedback], updatedAt: baseTime))
    XCTAssertThrowsError(try controller.adopt(actionID: candidate.id))
    XCTAssertEqual(try context.fetch(FetchDescriptor<Workout>()).count, 1)
  }

  func testNewPainOutsideSelectedPlanStillRequiresFreshConfirmation() throws {
    let (controller, repository, context, _, _) = try setup()
    let candidate = try XCTUnwrap(
      controller.evaluation?.candidates.first { $0.action == .keepPlan })
    try repository.saveCheckIn(
      .init(
        id: UUID(), localDate: AnalysisFingerprint.localDate(baseTime, timeZone: .gmt),
        timeZoneIdentifier: TimeZone.gmt.identifier,
        muscleFeedback: [
          .init(id: UUID(), muscleID: .quads, hasPain: true, recordedAt: baseTime)
        ], updatedAt: baseTime))
    XCTAssertThrowsError(try controller.adopt(actionID: candidate.id))
    XCTAssertEqual(try context.fetch(FetchDescriptor<Workout>()).count, 1)
  }

  func testTemplateChangeAndExistingWorkoutRejectDuplicateStart() throws {
    let (controller, _, context, routine, _) = try setup()
    let candidate = try XCTUnwrap(
      controller.evaluation?.candidates.first { $0.action == .keepPlan })
    routine.exercises[0].defaultSetCount = 5
    try context.save()
    XCTAssertThrowsError(try controller.adopt(actionID: candidate.id))
    XCTAssertEqual(try context.fetch(FetchDescriptor<Workout>()).count, 1)
    routine.exercises[0].defaultSetCount = 4
    let active = Workout(title: "正在训练", startedAt: baseTime)
    context.insert(active)
    try context.save()
    XCTAssertThrowsError(try controller.adopt(actionID: candidate.id))
    XCTAssertEqual(try context.fetch(FetchDescriptor<Workout>()).count, 2)
  }

  func testProfileTrainingFrequencyChangeRequiresFreshConfirmation() throws {
    let (controller, repository, context, _, _) = try setup()
    var profile = try XCTUnwrap(AnalysisFixtures.input(.manualOnly).profile)
    profile.updatedAt = baseTime.addingTimeInterval(-86_400)
    try repository.saveProfile(profile)
    controller.refresh()
    let candidate = try XCTUnwrap(
      controller.evaluation?.candidates.first { $0.action == .keepPlan })
    profile.trainingDaysPerWeek = 4
    profile.updatedAt = baseTime
    try repository.saveProfile(profile)
    XCTAssertThrowsError(try controller.adopt(actionID: candidate.id))
    XCTAssertEqual(try context.fetch(FetchDescriptor<Workout>()).count, 1)
  }

  func testSameCheckInIDEditedFeelingSleepOrMildSorenessRejectsOldReduceAdvice() throws {
    for edit in 0..<3 {
      let (controller, repository, context, _, clock) = try setup(historyAgeHours: 3)
      var checkIn = CheckInValue(
        id: UUID(), localDate: AnalysisFingerprint.localDate(baseTime, timeZone: .gmt),
        timeZoneIdentifier: TimeZone.gmt.identifier,
        feeling: .normal, sleepFeeling: .normal,
        muscleFeedback: [
          .init(id: UUID(), muscleID: .chest, soreness: .mild, recordedAt: baseTime)
        ], updatedAt: baseTime)
      try repository.saveCheckIn(checkIn)
      controller.refresh()
      let displayed = try XCTUnwrap(controller.evaluation)
      let candidate = try XCTUnwrap(displayed.candidates.first { $0.action == .reduceSets })
      switch edit {
      case 0: checkIn.feeling = .good
      case 1: checkIn.muscleFeedback[0].soreness = SorenessLevel.none
      default: checkIn.sleepFeeling = .poor
      }
      checkIn.updatedAt = baseTime.addingTimeInterval(1)
      try repository.saveCheckIn(checkIn)
      clock.value = baseTime.addingTimeInterval(2)
      let window = AnalysisWindow(
        start: clock.value.addingTimeInterval(-90 * 86_400), end: clock.value)
      let input = try repository.analysisInput(
        asOf: clock.value, window: window, timeZone: .gmt,
        health: .disconnected(window: window, asOf: clock.value))
      let trend = try TrendCalculator().calculate(input)
      let recovery = try RecoveryService().calculate(input)
      let fresh = try controller.makeRecommendationProvider()
        .evaluate(input: input, trend: trend, recovery: recovery)
      XCTAssertTrue(fresh.candidates.contains { $0.action == .reduceSets })
      XCTAssertNotEqual(fresh.feedbackIdentity, displayed.feedbackIdentity)
      XCTAssertThrowsError(
        try controller.adopt(
          actionID: candidate.id, parameters: ["retainedSetPercent": 50]))
      XCTAssertEqual(try context.fetch(FetchDescriptor<Workout>()).count, 1)
    }
  }

  func testUnsupportedTemplateModeAndUnallocatedHistoryNeverKeep() throws {
    let (unsupported, _, _, _, _) = try setup(mode: .cardio)
    XCTAssertFalse(unsupported.evaluation?.candidates.contains { $0.action == .keepPlan } == true)
    XCTAssertTrue(unsupported.evaluation?.candidates.contains { $0.action == .choosePlan } == true)
    let (unallocated, _, _, _, _) = try setup(withCoverageGap: true)
    XCTAssertFalse(unallocated.evaluation?.candidates.contains { $0.action == .keepPlan } == true)
    XCTAssertTrue(unallocated.evaluation?.candidates.contains { $0.action == .choosePlan } == true)
  }

  func testReportProviderRebuildsFactsAndContextFromCurrentSelection() throws {
    let (controller, repository, _, _, _) = try setup()
    let provider = try controller.makeRecommendationProvider()
    let window = AnalysisWindow(
      start: baseTime.addingTimeInterval(-90 * 86_400), end: baseTime)
    let input = try repository.analysisInput(
      asOf: baseTime, window: window, timeZone: .gmt,
      health: .disconnected(window: window, asOf: baseTime))
    let trend = try TrendCalculator().calculate(input)
    let recovery = try RecoveryService().calculate(input)
    let snapshot = try provider.snapshot(input: input, trend: trend, recovery: recovery)
    XCTAssertTrue(snapshot.candidates.contains { $0.action == .keepPlan })
    XCTAssertTrue(snapshot.facts.contains { $0.metric == "recommendation.selectedPlan" })
    XCTAssertEqual(snapshot.contextFingerprint, provider.context(trend: trend).fingerprint)
    controller.availableWeekdays = []
    let changed = try controller.makeRecommendationProvider()
      .snapshot(input: input, trend: trend, recovery: recovery)
    XCTAssertNotEqual(changed.contextFingerprint, snapshot.contextFingerprint)
    XCTAssertEqual(changed.candidates.map(\.action), [.rest, .lightActivity])
  }
}
