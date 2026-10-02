import SwiftData
import XCTest

@testable import Trainote

@MainActor
final class HealthRepositoryTests: XCTestCase {
  func testDietConfirmationInvalidatesOnEditAndHealthWeightsStayOutOfManualTable() throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let repo = SwiftDataAnalysisRepository(container: container)
    let context = ModelContext(container)
    let snapshot = AnalysisFixtures.health(.complete)
    let date = snapshot.samples[0].start
    let log = FoodLogEntry(
      loggedAt: date, mealType: .lunch, name: "合成午餐", servingDescription: "1份",
      quantity: 1, calories: 600, carbohydrates: 70, protein: 30, fat: 20)
    context.insert(log)
    try context.save()
    let timeZone = TimeZone(secondsFromGMT: 0)!
    let input = try repo.analysisInput(
      asOf: AnalysisFixtures.asOf, window: AnalysisFixtures.window,
      timeZone: timeZone, health: snapshot)
    XCTAssertFalse(try XCTUnwrap(input.nutrition.first).isComplete)
    try repo.confirmDiet(
      .init(
        id: UUID(), localDate: input.nutrition[0].localDate,
        timeZoneIdentifier: timeZone.identifier, confirmedAt: date,
        foodLogFingerprint: input.nutrition[0].logFingerprint))
    let confirmed = try repo.analysisInput(
      asOf: AnalysisFixtures.asOf, window: AnalysisFixtures.window,
      timeZone: timeZone, health: snapshot)
    XCTAssertTrue(confirmed.nutrition[0].isComplete)
    XCTAssertEqual(confirmed.weights.count, 1)
    XCTAssertTrue(try repo.manualRecords().weights.isEmpty)
    log.protein = 40
    try context.save()
    let changed = try repo.analysisInput(
      asOf: AnalysisFixtures.asOf, window: AnalysisFixtures.window,
      timeZone: timeZone, health: snapshot)
    XCTAssertFalse(changed.nutrition[0].isComplete)
    XCTAssertNotEqual(changed.inputFingerprint, confirmed.inputFingerprint)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyWeightEntry>()), 0)
  }

  func testFingerprintIgnoresReadTimestampAndKeepsExistingManualGoal() throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let repo = SwiftDataAnalysisRepository(container: container)
    let context = ModelContext(container)
    context.insert(NutritionGoal(calories: 2300, carbohydrates: 260, protein: 130, fat: 70))
    try context.save()
    var health = AnalysisFixtures.health(.complete)
    let first = try repo.analysisInput(
      asOf: AnalysisFixtures.asOf, window: AnalysisFixtures.window,
      timeZone: TimeZone(secondsFromGMT: 0)!, health: health)
    for index in health.statuses.indices { health.statuses[index].queriedAt.addTimeInterval(60) }
    health.fetchedAt.addTimeInterval(60)
    let second = try repo.analysisInput(
      asOf: AnalysisFixtures.asOf, window: AnalysisFixtures.window,
      timeZone: TimeZone(secondsFromGMT: 0)!, health: health)
    XCTAssertEqual(first.inputFingerprint, second.inputFingerprint)
    XCTAssertEqual(second.currentManualTargets?.calories, 2300)
    XCTAssertTrue(second.goalHistory.isEmpty)
    XCTAssertEqual(second.preferences.goalMode, .manual)
    XCTAssertFalse(second.coverage.isEmpty)
  }

  func testActiveProfileAndDailyFeedbackAreUniqueAndGoalHistoryIsImmutable() throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let repo = SwiftDataAnalysisRepository(container: container)
    var profile = AnalysisFixtures.input().profile!
    try repo.saveProfile(profile)
    profile.id = AnalysisFixtures.id(510)
    try repo.saveProfile(profile)
    XCTAssertEqual(try repo.manualRecords().profiles.filter(\.isActive).count, 1)
    var checkIn = AnalysisFixtures.input().checkIns[0]
    try repo.saveCheckIn(checkIn)
    checkIn.feeling = .tired
    checkIn.muscleFeedback[0].hasPain = true
    try repo.saveCheckIn(checkIn)
    XCTAssertEqual(try repo.manualRecords().checkIns[0].muscleFeedback[0].hasPain, true)
    checkIn.id = UUID()
    XCTAssertThrowsError(try repo.saveCheckIn(checkIn))
    let date = AnalysisFixtures.asOf
    var goal = NutritionGoalRevisionValue(
      id: UUID(), effectiveAt: date,
      targets: .init(calories: 2000, carbohydrates: 240, protein: 120, fat: 60),
      origin: .suggested, proposalID: "proposal-1", calculationVersion: "test", createdAt: date)
    try repo.appendGoalRevision(goal)
    try repo.appendGoalRevision(goal)
    goal.targets.calories = 2200
    XCTAssertThrowsError(try repo.appendGoalRevision(goal))
    goal.id = UUID()
    XCTAssertThrowsError(try repo.appendGoalRevision(goal))
    XCTAssertEqual(try repo.manualRecords().goalRevisions.count, 1)
    XCTAssertEqual(try repo.manualRecords().goalRevisions[0].targets.calories, 2000)
  }

  func testRIRAndRoleSurviveHistoryEditButNewWorkoutDoesNotReuseRIR() throws {
    let workout = Workout(title: "合成训练")
    let exercise = WorkoutExercise(
      sourceExerciseID: "0025", nameEnSnapshot: "Bench", nameZhSnapshot: "卧推",
      orderIndex: 0, trackingMode: .strength)
    exercise.strengthSets = [
      StrengthSet(
        orderIndex: 0, weightKilograms: 60, repetitions: 8,
        isCompleted: true, rir: 1, setRole: .working)
    ]
    workout.exercises = [exercise]
    let editing = WorkoutHistoryFactory.copy(
      of: workout, startedAt: AnalysisFixtures.asOf,
      status: .completed, preserveCompletion: true)
    XCTAssertEqual(editing.exercises[0].strengthSets[0].rir, 1)
    XCTAssertEqual(editing.exercises[0].strengthSets[0].setRole, .working)
    let next = WorkoutHistoryFactory.copy(
      of: workout, startedAt: AnalysisFixtures.asOf, status: .inProgress)
    XCTAssertNil(next.exercises[0].strengthSets[0].rir)
    XCTAssertFalse(next.exercises[0].strengthSets[0].isCompleted)
    let invalid = StrengthSet(orderIndex: 0, repetitions: 8, rir: 6)
    XCTAssertFalse(invalid.isValid(for: .strength))
  }
}
