import SwiftData
import XCTest

@testable import Trainote

@MainActor
final class RecoveryWorkflowTests: XCTestCase {
  func testNewWorkoutDefaultsWorkingHistoryPreservesRoleAndRIRAndRepeatClearsThem() throws {
    let catalog = ExerciseCatalog()
    let item = try XCTUnwrap(catalog.items.first { $0.id == "0025" })
    let exercise = RoutineFactory.workoutExercise(from: item, orderIndex: 0)
    XCTAssertEqual(exercise.strengthSets[0].setRole, .working)
    exercise.strengthSets[0].rir = 1
    exercise.strengthSets[0].isCompleted = true
    exercise.strengthSets[0].setRole = .warmup
    let original = Workout(
      title: "合成卧推", startedAt: .now.addingTimeInterval(-3600), endedAt: .now,
      status: .completed, exercises: [exercise])
    let edit = WorkoutHistoryFactory.copy(
      of: original, startedAt: original.startedAt,
      status: .completed, preserveCompletion: true)
    XCTAssertEqual(edit.exercises[0].strengthSets[0].rir, 1)
    XCTAssertEqual(edit.exercises[0].strengthSets[0].setRole, .warmup)
    let new = WorkoutHistoryFactory.copy(of: original, startedAt: .now, status: .inProgress)
    XCTAssertNil(new.exercises[0].strengthSets[0].rir)
    XCTAssertFalse(new.exercises[0].strengthSets[0].isCompleted)
    XCTAssertEqual(new.exercises[0].strengthSets[0].setRole, .warmup)
    original.exercises[0].strengthSets[0].setRole = .unknown
    let legacyRepeat = WorkoutHistoryFactory.copy(
      of: original, startedAt: .now, status: .inProgress)
    XCTAssertEqual(legacyRepeat.exercises[0].strengthSets[0].setRole, .working)
    XCTAssertEqual(original.exercises[0].strengthSets[0].setRole, .unknown)
    let routine = WorkoutHistoryFactory.routine(from: original)
    let fromRoutine = RoutineFactory.workout(from: routine)
    XCTAssertEqual(fromRoutine.exercises[0].strengthSets[0].setRole, .working)
    XCTAssertNil(fromRoutine.exercises[0].strengthSets[0].rir)
  }

  func testRepositoryFeedbackUpdateAndWorkoutEditDeleteRebuildScore() throws {
    let helper = RecoveryCalculatorTests()
    let now = helper.now
    let container = try PersistenceController.makeContainer(inMemory: true)
    let repo = SwiftDataAnalysisRepository(container: container)
    let context = ModelContext(container)
    let workout = Workout(
      title: "合成卧推", startedAt: now.addingTimeInterval(-3600), endedAt: now, status: .completed)
    let exercise = WorkoutExercise(
      sourceExerciseID: "0025", nameEnSnapshot: "bench", nameZhSnapshot: "卧推",
      orderIndex: 0, trackingMode: .strength)
    let set = StrengthSet(
      orderIndex: 0, weightKilograms: 60, repetitions: 8, isCompleted: true, rir: 2,
      setRole: .working)
    set.exercise = exercise
    exercise.strengthSets = [set]
    exercise.workout = workout
    workout.exercises = [exercise]
    context.insert(workout)
    try context.save()
    let window = AnalysisWindow(
      start: now.addingTimeInterval(-90 * 86_400), end: now.addingTimeInterval(1))
    func calculate() throws -> RecoveryResult {
      try helper.calculator().calculate(
        repo.analysisInput(
          asOf: now, window: window, timeZone: .gmt,
          health: .disconnected(window: window, asOf: now)))
    }
    let original = try calculate()
    var check = CheckInValue(
      id: UUID(), localDate: AnalysisFingerprint.localDate(now, timeZone: .gmt),
      timeZoneIdentifier: "GMT",
      muscleFeedback: [.init(id: UUID(), muscleID: .chest, hasPain: true, recordedAt: now)],
      updatedAt: now)
    try repo.saveCheckIn(check)
    XCTAssertEqual(try helper.chest(calculate()).state, .limited)
    check.muscleFeedback[0].hasPain = false
    try repo.saveCheckIn(check)
    XCTAssertFalse(try helper.chest(calculate()).hasPain)
    set.rir = 0
    try context.save()
    let edited = try calculate()
    XCTAssertNotEqual(edited.inputFingerprint, original.inputFingerprint)
    XCTAssertLessThan(
      try XCTUnwrap(helper.chest(edited).score), try XCTUnwrap(helper.chest(original).score))
    context.delete(workout)
    try context.save()
    XCTAssertNil(try helper.chest(calculate()).score)
  }

  func testPromptIsOptionalOncePerDayAndDoesNotChaseInactiveUsers() throws {
    let repo = SwiftDataAnalysisRepository(
      container: try PersistenceController.makeContainer(inMemory: true))
    let now = Date.now
    XCTAssertTrue(
      try RecoveryCheckInPrompt.offer(
        repository: repo, records: repo.manualRecords(), date: now, timeZone: .gmt))
    XCTAssertFalse(
      try RecoveryCheckInPrompt.offer(
        repository: repo, records: repo.manualRecords(), date: now, timeZone: .gmt))
    XCTAssertTrue(try repo.manualRecords().checkIns.isEmpty)
    XCTAssertFalse(
      try RecoveryCheckInPrompt.offer(
        repository: repo, records: repo.manualRecords(), date: now.addingTimeInterval(9 * 86_400),
        timeZone: .gmt))
    var preferences = try repo.manualRecords().preferences
    preferences.checkInPromptsEnabled = false
    try repo.savePreferences(preferences)
    XCTAssertFalse(
      try RecoveryCheckInPrompt.offer(
        repository: repo, records: repo.manualRecords(), date: now.addingTimeInterval(86_400),
        timeZone: .gmt))
  }

  func testFreshReportRecomputesRecoveryAndRemovesHealthDerivedBaseline() async throws {
    let helper = RecoveryCalculatorTests()
    let now = helper.now
    let container = try PersistenceController.makeContainer(inMemory: true)
    let repo = SwiftDataAnalysisRepository(container: container)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "recovery-report-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    try consent.grant(.healthData, version: LocalConsentStore.healthConsentVersion, at: now)
    try consent.grant(.aiReports, version: LocalConsentStore.aiConsentVersion, at: now)
    let health = FixtureHealthDataProvider()
    let window = AnalysisWindow(
      start: now.addingTimeInterval(-90 * 86_400), end: now.addingTimeInterval(1))
    let samples: [HealthSample] = (0..<24).map { index in
      let date = now.addingTimeInterval(-Double(index) * 86_400)
      return .init(
        id: UUID(), type: .heartRateVariabilitySDNN, start: date, end: date,
        value: 50, unit: .milliseconds,
        source: .init(bundleIdentifier: "synthetic.watch", name: "Synthetic", productType: "Watch"),
        definition: "SDNN", measurementContext: "unspecified")
    }
    health.snapshot = .init(
      window: window, fetchedAt: now, isFresh: true, samples: samples,
      statuses: [.init(type: .heartRateVariabilitySDNN, state: .samplesAvailable, queriedAt: now)])
    let builder = ReportSnapshotBuilder(
      repository: repo, health: health, consent: consent,
      trend: FixtureTrendCalculator(), recovery: try RecoveryService(),
      recommendations: FixtureRecommendationProvider())
    let before = try await builder.prepare(
      type: .recovery, window: window, asOf: now, timeZone: .gmt,
      knowledgeVersion: "synthetic", consentVersion: LocalConsentStore.aiConsentVersion)
    let baseline = try XCTUnwrap(
      before.input.facts.first { $0.id == "recovery.systemic.heartRateVariabilitySDNN.baseline" })
    XCTAssertEqual(baseline.value, 50)
    XCTAssertEqual(baseline.dependencies.filter { $0.kind == .healthSample }.count, 21)
    health.snapshot.samples = []
    let after = try await builder.prepare(
      type: .recovery, window: window, asOf: now, timeZone: .gmt,
      knowledgeVersion: "synthetic", consentVersion: LocalConsentStore.aiConsentVersion)
    XCTAssertFalse(after.input.facts.contains { $0.id == baseline.id })
    XCTAssertFalse(after.input.facts.flatMap(\.dependencies).contains { $0.kind == .healthSample })
    XCTAssertEqual(health.freshRequests, 2)
  }

}
