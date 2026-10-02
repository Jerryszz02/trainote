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

  private func setup(mode: TrackingMode = .strength, withCoverageGap: Bool = false) throws
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
      title: "原有训练", startedAt: baseTime.addingTimeInterval(-49 * 3600),
      endedAt: baseTime.addingTimeInterval(-48 * 3600), status: .completed)
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

  func testUnsupportedTemplateModeAndUnallocatedHistoryNeverKeep() throws {
    let (unsupported, _, _, _, _) = try setup(mode: .cardio)
    XCTAssertFalse(unsupported.evaluation?.candidates.contains { $0.action == .keepPlan } == true)
    XCTAssertTrue(unsupported.evaluation?.candidates.contains { $0.action == .choosePlan } == true)
    let (unallocated, _, _, _, _) = try setup(withCoverageGap: true)
    XCTAssertFalse(unallocated.evaluation?.candidates.contains { $0.action == .keepPlan } == true)
    XCTAssertTrue(unallocated.evaluation?.candidates.contains { $0.action == .choosePlan } == true)
  }
}
