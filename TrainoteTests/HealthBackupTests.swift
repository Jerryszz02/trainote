import SwiftData
import XCTest

@testable import Trainote

@MainActor
final class HealthBackupTests: XCTestCase {
  func testActualFrozenV1JSONImportsWithoutInventingRIRAndRepeats() throws {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "backup-v1", withExtension: "json"))
    let data = try Data(contentsOf: url)
    let decoded = try BackupArchiveService.decode(data)
    XCTAssertEqual(decoded.schemaVersion, 1)
    XCTAssertNil(decoded.manualHealth)
    let container = try PersistenceController.makeContainer(inMemory: true)
    XCTAssertEqual(try BackupArchiveService.importData(data, into: container).inserted, 5)
    XCTAssertEqual(try BackupArchiveService.importData(data, into: container).inserted, 0)
    let context = ModelContext(container)
    let set = try XCTUnwrap(context.fetch(FetchDescriptor<StrengthSet>()).first)
    XCTAssertNil(set.rir)
    XCTAssertEqual(set.setRole, .unknown)
    XCTAssertEqual(set.durationSeconds, 30)
    XCTAssertEqual(set.weightKilograms, 60)
    XCTAssertEqual(set.id.uuidString, "33333333-3333-3333-3333-333333333333")
    XCTAssertNotNil(try context.fetch(FetchDescriptor<Workout>()).first?.restEndsAt)
    XCTAssertEqual(try context.fetch(FetchDescriptor<FoodLogEntry>()).first?.calories, 600)
  }

  func testNewManualFactsRoundTripWithoutRestoringPermissions() throws {
    let source = try PersistenceController.makeContainer(inMemory: true)
    let repo = SwiftDataAnalysisRepository(container: source)
    let fixture = AnalysisFixtures.input()
    try repo.saveProfile(fixture.profile!)
    let date = AnalysisFixtures.asOf
    try repo.saveWeight(
      .init(
        id: AnalysisFixtures.id(401), measuredAt: date, kilograms: 70,
        timeZoneIdentifier: "UTC", createdAt: date, updatedAt: date))
    try repo.saveCheckIn(fixture.checkIns[0])
    try repo.confirmDiet(
      .init(
        id: AnalysisFixtures.id(402), localDate: "2026-10-03",
        timeZoneIdentifier: "UTC", confirmedAt: date, foodLogFingerprint: "synthetic-fingerprint"))
    try repo.appendGoalRevision(
      .init(
        id: AnalysisFixtures.id(403), effectiveAt: date,
        targets: .init(calories: 2000, carbohydrates: 240, protein: 120, fat: 60),
        origin: .suggested, proposalID: "synthetic-proposal", calculationVersion: "test-v1",
        createdAt: date))
    try repo.savePreferences(.init(goalMode: .suggested, preferredWeightSourceID: "fixture.watch"))
    let context = ModelContext(source)
    let workout = Workout(title: "合成训练")
    let exercise = WorkoutExercise(
      sourceExerciseID: "0025", nameEnSnapshot: "Bench", nameZhSnapshot: "卧推",
      orderIndex: 0, trackingMode: .strength)
    let set = StrengthSet(
      orderIndex: 0, weightKilograms: 60, repetitions: 8, isCompleted: true,
      rir: 2, setRole: .working)
    set.exercise = exercise
    exercise.strengthSets = [set]
    exercise.workout = workout
    workout.exercises = [exercise]
    context.insert(workout)
    let data = try BackupArchiveService.export(context: context)
    let decoded = try BackupArchiveService.decode(data)
    XCTAssertEqual(decoded.schemaVersion, 2)
    XCTAssertEqual(decoded.counts.manualHealthObjects, 7)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(
      Set(object.keys),
      Set([
        "schemaVersion", "createdAt", "workouts", "routines", "foodPresets",
        "mealTemplates", "foodLogs", "nutritionGoals", "manualHealth",
      ]))
    let text = String(decoding: data, as: UTF8.self)
    for excluded in ["anchors", "consent", "token", "HealthSample", "AIReport", "healthCache"] {
      XCTAssertFalse(text.contains(excluded))
    }
    let destination = try PersistenceController.makeContainer(inMemory: true)
    let first = try BackupArchiveService.importData(data, into: destination)
    XCTAssertEqual(first.inserted, 10)
    XCTAssertEqual(try BackupArchiveService.importData(data, into: destination).skipped, 10)
    XCTAssertEqual(
      try SwiftDataAnalysisRepository(container: destination).manualRecords(),
      try repo.manualRecords())
    let restored = try XCTUnwrap(
      ModelContext(destination).fetch(FetchDescriptor<StrengthSet>()).first)
    XCTAssertEqual(restored.rir, 2)
    XCTAssertEqual(restored.setRole, .working)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let consent = try LocalConsentStore(url: directory.appendingPathComponent("consent.json"))
    XCTAssertNil(consent.record(for: .healthData))
    XCTAssertNil(consent.record(for: .aiReports))
  }

  func testFutureVersionAndExistingLimitsAreRejected() throws {
    XCTAssertThrowsError(try BackupArchiveService.decode(Data("{\"schemaVersion\":99}".utf8))) {
      XCTAssertEqual($0 as? BackupArchiveError, .unsupportedVersion(99))
    }
    XCTAssertThrowsError(try BackupArchiveService.decode(Data(count: BackupArchive.maxBytes + 1))) {
      XCTAssertEqual($0 as? BackupArchiveError, .tooLarge)
    }
    let weight = ManualWeightValue(
      id: UUID(), measuredAt: AnalysisFixtures.asOf, kilograms: 70,
      timeZoneIdentifier: "UTC", createdAt: AnalysisFixtures.asOf, updatedAt: AnalysisFixtures.asOf)
    let archive = BackupArchive(
      schemaVersion: 2, createdAt: AnalysisFixtures.asOf,
      workouts: [], routines: [], foodPresets: [], mealTemplates: [], foodLogs: [],
      nutritionGoals: [],
      manualHealth: .init(
        profiles: [], weights: Array(repeating: weight, count: 100_001),
        checkIns: [], dietCompleteness: [], goalRevisions: [], preferences: nil))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    XCTAssertThrowsError(try BackupArchiveService.decode(encoder.encode(archive))) {
      XCTAssertEqual($0 as? BackupArchiveError, .tooLarge)
    }
  }

  func testProfileAndCrossTypeConflictsDoNotPartiallyImport() throws {
    let source = try PersistenceController.makeContainer(inMemory: true)
    let sourceRepo = SwiftDataAnalysisRepository(container: source)
    let profile = AnalysisFixtures.input().profile!
    try sourceRepo.saveProfile(profile)
    let date = AnalysisFixtures.asOf
    try sourceRepo.saveWeight(
      .init(
        id: AnalysisFixtures.id(410), measuredAt: date, kilograms: 70,
        timeZoneIdentifier: "UTC", createdAt: date, updatedAt: date))
    let data = try BackupArchiveService.export(context: ModelContext(source))
    let destination = try PersistenceController.makeContainer(inMemory: true)
    let repo = SwiftDataAnalysisRepository(container: destination)
    var other = profile
    other.id = AnalysisFixtures.id(411)
    try repo.saveProfile(other)
    XCTAssertThrowsError(try BackupArchiveService.importData(data, into: destination))
    XCTAssertTrue(try repo.manualRecords().weights.isEmpty)
    let empty = try PersistenceController.makeContainer(inMemory: true)
    let context = ModelContext(empty)
    context.insert(
      FoodPreset(
        id: profile.id, name: "冲突", caloriesPerServing: 1,
        carbohydratesPerServing: 1, proteinPerServing: 1, fatPerServing: 1))
    try context.save()
    XCTAssertThrowsError(try BackupArchiveService.importData(data, into: empty))
    XCTAssertEqual(try ModelContext(empty).fetchCount(FetchDescriptor<BodyWeightEntry>()), 0)
  }

  func testChangedSharedGoalCannotImportNewHistoryOrAnyOtherRecords() throws {
    let date = AnalysisFixtures.asOf
    let goalID = AnalysisFixtures.id(900)
    func containerWithOldGoal() throws -> ModelContainer {
      let container = try PersistenceController.makeContainer(inMemory: true)
      let context = ModelContext(container)
      context.insert(
        NutritionGoal(
          id: goalID, calories: 2000, carbohydrates: 240,
          protein: 120, fat: 60, updatedAt: date))
      try context.save()
      return container
    }
    let source = try containerWithOldGoal()
    let sourceRepo = SwiftDataAnalysisRepository(container: source)
    let newGoal = NutritionGoalRevisionValue(
      id: AnalysisFixtures.id(901), effectiveAt: date.addingTimeInterval(10),
      targets: .init(calories: 2200, carbohydrates: 260, protein: 140, fat: 60),
      origin: .suggested, proposalID: "backup-goal-conflict", calculationVersion: "fixture",
      createdAt: date.addingTimeInterval(10))
    _ = try sourceRepo.applyGoalRevision(
      .init(revision: newGoal, expectedState: sourceRepo.goalRevisionState()))
    let sourceContext = ModelContext(source)
    sourceContext.insert(
      FoodPreset(
        id: AnalysisFixtures.id(902), name: "应一起拒绝的合成食物",
        caloriesPerServing: 100, carbohydratesPerServing: 10, proteinPerServing: 10,
        fatPerServing: 2))
    let data = try BackupArchiveService.export(context: sourceContext)
    let destination = try containerWithOldGoal()
    let repo = SwiftDataAnalysisRepository(container: destination)
    try repo.saveWeight(
      .init(
        id: AnalysisFixtures.id(903), measuredAt: date, kilograms: 68,
        timeZoneIdentifier: "UTC", createdAt: date, updatedAt: date))
    let stateBefore = try repo.goalRevisionState()
    let manualBefore = try repo.manualRecords()
    XCTAssertThrowsError(try BackupArchiveService.importData(data, into: destination)) {
      XCTAssertEqual($0 as? BackupArchiveError, .goalStateConflict)
    }
    XCTAssertEqual(try repo.goalRevisionState(), stateBefore)
    XCTAssertEqual(try repo.manualRecords(), manualBefore)
    XCTAssertEqual(try ModelContext(destination).fetchCount(FetchDescriptor<FoodPreset>()), 0)
    XCTAssertEqual(
      try ModelContext(destination).fetch(FetchDescriptor<NutritionGoal>()).first?.calories, 2000)
  }

  func testConsistentGoalHistoryBackupCanBeRepeatedAtArchiveDatePrecision() throws {
    let date = AnalysisFixtures.asOf.addingTimeInterval(0.125)
    let container = try PersistenceController.makeContainer(inMemory: true)
    let context = ModelContext(container)
    context.insert(
      NutritionGoal(calories: 2000, carbohydrates: 240, protein: 120, fat: 60, updatedAt: date))
    try context.save()
    let repo = SwiftDataAnalysisRepository(container: container)
    let revision = NutritionGoalRevisionValue(
      id: UUID(), effectiveAt: date.addingTimeInterval(10),
      targets: .init(calories: 2200, carbohydrates: 260, protein: 140, fat: 60),
      origin: .manual, createdAt: date.addingTimeInterval(10))
    _ = try repo.applyGoalRevision(
      .init(revision: revision, expectedState: repo.goalRevisionState()))
    let data = try BackupArchiveService.export(context: ModelContext(container))
    let originalState = try repo.goalRevisionState()
    let repeated = try BackupArchiveService.importData(data, into: container)
    XCTAssertEqual(repeated.inserted, 0)
    XCTAssertEqual(repeated.skipped, 3)
    XCTAssertEqual(try repo.goalRevisionState(), originalState)
    let destination = try PersistenceController.makeContainer(inMemory: true)
    XCTAssertEqual(try BackupArchiveService.importData(data, into: destination).inserted, 3)
    let restored = try SwiftDataAnalysisRepository(container: destination).goalRevisionState()
    XCTAssertEqual(restored, originalState)
    XCTAssertEqual(restored.currentGoal?.targets, revision.targets)
    XCTAssertEqual(restored.latestRevisionID, revision.id)
  }

  func testRapidAdoptionUndoBackupPreservesOrderAndAllowsNextAdoption() throws {
    let date = AnalysisFixtures.asOf
    let source = try PersistenceController.makeContainer(inMemory: true)
    let context = ModelContext(source)
    let before = NutritionTargets(calories: 2000, carbohydrates: 240, protein: 120, fat: 60)
    context.insert(
      NutritionGoal(
        calories: before.calories, carbohydrates: before.carbohydrates,
        protein: before.protein, fat: before.fat, updatedAt: date.addingTimeInterval(-60)))
    try context.save()
    let repo = SwiftDataAnalysisRepository(container: source)
    let adoption = NutritionGoalRevisionValue(
      id: UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!,
      effectiveAt: date.addingTimeInterval(0.2),
      targets: .init(calories: 2200, carbohydrates: 260, protein: 140, fat: 60),
      origin: .suggested, proposalID: "rapid-adoption", calculationVersion: "fixture",
      createdAt: date.addingTimeInterval(0.2))
    let applied = try repo.applyGoalRevision(
      .init(revision: adoption, expectedState: repo.goalRevisionState()))
    let undo = NutritionGoalRevisionValue(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      effectiveAt: date.addingTimeInterval(0.8), targets: before, origin: .manual,
      reversesRevisionID: adoption.id, createdAt: date.addingTimeInterval(0.8))
    let undone = try repo.applyGoalRevision(.init(revision: undo, expectedState: applied.state))
    let data = try BackupArchiveService.export(context: ModelContext(source))
    XCTAssertEqual(try BackupArchiveService.importData(data, into: source).inserted, 0)
    XCTAssertEqual(try repo.goalRevisionState(), undone.state)
    let destination = try PersistenceController.makeContainer(inMemory: true)
    XCTAssertEqual(try BackupArchiveService.importData(data, into: destination).inserted, 4)
    let restored = SwiftDataAnalysisRepository(container: destination)
    XCTAssertEqual(try restored.goalRevisionState(), undone.state)
    XCTAssertEqual(
      try restored.manualRecords().goalRevisions.sorted { $0.id.uuidString < $1.id.uuidString },
      try repo.manualRecords().goalRevisions.sorted { $0.id.uuidString < $1.id.uuidString })
    XCTAssertEqual(try BackupArchiveService.importData(data, into: destination).skipped, 4)
    XCTAssertEqual(try restored.goalRevisionState(), undone.state)
    var next = adoption
    next.id = AnalysisFixtures.id(910)
    next.proposalID = "after-rapid-undo"
    next.effectiveAt = date.addingTimeInterval(0.9)
    next.createdAt = next.effectiveAt
    let continued = try restored.applyGoalRevision(
      .init(revision: next, expectedState: restored.goalRevisionState()))
    XCTAssertEqual(continued.state.currentGoal?.targets, adoption.targets)
    XCTAssertEqual(continued.state.latestRevisionID, next.id)
  }

  func testSubsecondBaselineBackupPreservesFirstAdoptionAndUndo() throws {
    let date = AnalysisFixtures.asOf
    let source = try PersistenceController.makeContainer(inMemory: true)
    let context = ModelContext(source)
    let before = NutritionTargets(calories: 2000, carbohydrates: 240, protein: 120, fat: 60)
    let originalDate = date.addingTimeInterval(0.1)
    context.insert(
      NutritionGoal(
        calories: before.calories, carbohydrates: before.carbohydrates,
        protein: before.protein, fat: before.fat, updatedAt: originalDate))
    try context.save()
    let repo = SwiftDataAnalysisRepository(container: source)
    // The generated baseline UUID sorts after this ID if its effectiveAt loses precision.
    let adoption = NutritionGoalRevisionValue(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
      effectiveAt: date.addingTimeInterval(0.2),
      targets: .init(calories: 2200, carbohydrates: 260, protein: 140, fat: 60),
      origin: .manual, createdAt: date.addingTimeInterval(0.2))
    let applied = try repo.applyGoalRevision(
      .init(revision: adoption, expectedState: repo.goalRevisionState()))
    let data = try BackupArchiveService.export(context: ModelContext(source))
    let destination = try PersistenceController.makeContainer(inMemory: true)
    XCTAssertEqual(try BackupArchiveService.importData(data, into: destination).inserted, 3)
    let restored = SwiftDataAnalysisRepository(container: destination)
    XCTAssertEqual(try restored.goalRevisionState(), applied.state)
    let baseline = try XCTUnwrap(
      restored.manualRecords().goalRevisions.first { $0.id == applied.insertedBaselineRevisionID })
    XCTAssertEqual(baseline.effectiveAt, originalDate)
    XCTAssertEqual(baseline.createdAt, adoption.createdAt)
    let undo = NutritionGoalRevisionValue(
      id: AnalysisFixtures.id(911), effectiveAt: date.addingTimeInterval(0.3),
      targets: before, origin: .manual, reversesRevisionID: adoption.id,
      createdAt: date.addingTimeInterval(0.3))
    let undone = try restored.applyGoalRevision(
      .init(revision: undo, expectedState: restored.goalRevisionState()))
    XCTAssertEqual(undone.state.currentGoal?.targets, before)
    XCTAssertEqual(undone.state.latestRevisionID, undo.id)
  }

  func testBackupPreservesAdjacentRepresentableDatesWithoutEpochConversion() throws {
    let now = AnalysisFixtures.asOf.timeIntervalSinceReferenceDate
    let intervals = [
      Double.leastNonzeroMagnitude, Double.leastNormalMagnitude,
      (-0.25).nextDown, (-0.25).nextUp, 0.25.nextDown, 0.25.nextUp,
      now.nextDown, now, now.nextUp,
    ]
    let source = try PersistenceController.makeContainer(inMemory: true)
    let context = ModelContext(source)
    var expected: [UUID: UInt64] = [:]
    for interval in intervals {
      let goal = NutritionGoal(
        calories: 2000, carbohydrates: 240, protein: 120, fat: 60,
        updatedAt: Date(timeIntervalSinceReferenceDate: interval))
      expected[goal.id] = interval.bitPattern
      context.insert(goal)
    }
    let data = try BackupArchiveService.export(context: context)
    let decoded = try BackupArchiveService.decode(data)
    for goal in decoded.nutritionGoals {
      XCTAssertEqual(goal.updatedAt.timeIntervalSinceReferenceDate.bitPattern, expected[goal.id])
    }
    let destination = try PersistenceController.makeContainer(inMemory: true)
    XCTAssertEqual(try BackupArchiveService.importData(data, into: destination).inserted, intervals.count)
    for goal in try ModelContext(destination).fetch(FetchDescriptor<NutritionGoal>()) {
      XCTAssertEqual(goal.updatedAt.timeIntervalSinceReferenceDate.bitPattern, expected[goal.id])
    }
    XCTAssertEqual(try BackupArchiveService.importData(data, into: destination).skipped, intervals.count)
  }

  func testLegacySecondPrecisionV2StillImportsAndRepeatsWithoutChangingSourceDates() throws {
    let date = AnalysisFixtures.asOf.addingTimeInterval(0.125)
    let source = try PersistenceController.makeContainer(inMemory: true)
    let context = ModelContext(source)
    context.insert(
      NutritionGoal(calories: 2000, carbohydrates: 240, protein: 120, fat: 60, updatedAt: date))
    try context.save()
    let repo = SwiftDataAnalysisRepository(container: source)
    let revision = NutritionGoalRevisionValue(
      id: AnalysisFixtures.id(912), effectiveAt: date.addingTimeInterval(10),
      targets: .init(calories: 2200, carbohydrates: 260, protein: 140, fat: 60),
      origin: .manual, createdAt: date.addingTimeInterval(10))
    let applied = try repo.applyGoalRevision(
      .init(revision: revision, expectedState: repo.goalRevisionState()))
    let archive = try BackupArchiveService.decode(
      BackupArchiveService.export(context: ModelContext(source)))
    let oldEncoder = JSONEncoder()
    oldEncoder.dateEncodingStrategy = .iso8601
    let legacyData = try oldEncoder.encode(archive)
    XCTAssertEqual(try BackupArchiveService.decode(legacyData).schemaVersion, 2)
    XCTAssertEqual(try BackupArchiveService.importData(legacyData, into: source).skipped, 3)
    XCTAssertEqual(try repo.goalRevisionState(), applied.state)
    let destination = try PersistenceController.makeContainer(inMemory: true)
    XCTAssertEqual(try BackupArchiveService.importData(legacyData, into: destination).inserted, 3)
    XCTAssertEqual(try BackupArchiveService.importData(legacyData, into: destination).skipped, 3)
    let restored = SwiftDataAnalysisRepository(container: destination)
    XCTAssertEqual(try restored.goalRevisionState().latestRevisionID, revision.id)
    var next = revision
    next.id = AnalysisFixtures.id(913)
    next.createdAt = date.addingTimeInterval(20)
    next.effectiveAt = next.createdAt
    XCTAssertEqual(
      try restored.applyGoalRevision(
        .init(revision: next, expectedState: restored.goalRevisionState())).state.latestRevisionID,
      next.id)
  }

  func testPreciseBackupDoesNotIgnoreSubsecondSharedGoalConflicts() throws {
    let date = AnalysisFixtures.asOf.addingTimeInterval(0.125)
    let source = try PersistenceController.makeContainer(inMemory: true)
    let context = ModelContext(source)
    let goal = NutritionGoal(
      calories: 2000, carbohydrates: 240, protein: 120, fat: 60, updatedAt: date)
    context.insert(goal)
    try context.save()
    let repo = SwiftDataAnalysisRepository(container: source)
    let revision = NutritionGoalRevisionValue(
      id: AnalysisFixtures.id(914), effectiveAt: date.addingTimeInterval(10),
      targets: .init(calories: 2200, carbohydrates: 260, protein: 140, fat: 60),
      origin: .manual, createdAt: date.addingTimeInterval(10))
    let applied = try repo.applyGoalRevision(
      .init(revision: revision, expectedState: repo.goalRevisionState()))
    var archive = try BackupArchiveService.decode(
      BackupArchiveService.export(context: ModelContext(source)))
    archive.nutritionGoals[0].updatedAt = Date(
      timeIntervalSinceReferenceDate: archive.nutritionGoals[0].updatedAt
        .timeIntervalSinceReferenceDate.nextUp)
    let data = try JSONEncoder().encode(archive)
    XCTAssertThrowsError(try BackupArchiveService.importData(data, into: source)) {
      XCTAssertEqual($0 as? BackupArchiveError, .goalStateConflict)
    }
    XCTAssertEqual(try repo.goalRevisionState(), applied.state)
  }

  func testSaveFailureLeavesOldStoreUntouched() throws {
    let url = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "backup-v1", withExtension: "json"))
    let data = try Data(contentsOf: url)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = directory.appendingPathComponent("readonly.store")
    try autoreleasepool {
      let writable = try PersistenceController.makeContainer(storeURL: store)
      try writable.mainContext.save()
    }
    let readonly = try PersistenceController.makeContainer(storeURL: store, allowsSave: false)
    XCTAssertThrowsError(try BackupArchiveService.importData(data, into: readonly))
    XCTAssertEqual(try ModelContext(readonly).fetchCount(FetchDescriptor<Workout>()), 0)
    XCTAssertEqual(try ModelContext(readonly).fetchCount(FetchDescriptor<FoodLogEntry>()), 0)
  }
}
