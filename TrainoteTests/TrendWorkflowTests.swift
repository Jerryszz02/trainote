import SwiftData
import XCTest

@testable import Trainote

@MainActor
final class TrendWorkflowTests: XCTestCase {
  func testSuggestedRequiresExplicitAdoptionAndSameProposalIsIdempotent() throws {
    var input = TrendTestData.input(cold: true)
    let proposal = try XCTUnwrap(TrendCalculator().calculate(input).proposal)
    var writes: [NutritionGoalRevisionValue] = []
    let workflow = TrendGoalWorkflow { revision, expected, latest, preferences in
      XCTAssertEqual(expected, input.currentManualTargets)
      XCTAssertNil(latest)
      XCTAssertNil(preferences)
      writes.append(revision)
    }
    XCTAssertThrowsError(
      try workflow.adopt(proposalID: proposal.id, input: input, automatically: true))
    XCTAssertTrue(writes.isEmpty)
    let revision = try workflow.adopt(proposalID: proposal.id, input: input)
    XCTAssertEqual(revision.origin, .suggested)
    XCTAssertEqual(revision.effectiveAt, TrendTestData.calendar.start(input.asOf))
    XCTAssertEqual(writes.count, 1)
    input.goalHistory = [revision]
    input.currentManualTargets = revision.targets
    XCTAssertEqual(try workflow.adopt(proposalID: proposal.id, input: input), revision)
    XCTAssertEqual(writes.count, 1)
  }
  func testAutomaticExplicitOptInAndDeterministicRevision() throws {
    var input = TrendTestData.input()
    input.preferences.goalMode = .automatic
    let proposal = try XCTUnwrap(TrendCalculator().calculate(input).proposal)
    let workflow = TrendGoalWorkflow { _, _, _, _ in }
    let first = try workflow.adopt(proposalID: proposal.id, input: input, automatically: true)
    let second = try workflow.adopt(proposalID: proposal.id, input: input, automatically: true)
    XCTAssertEqual(first, second)
    XCTAssertEqual(first.origin, .automatic)
  }

  func testInitialGoalRequiresUserAdoptionEvenWhenAutomaticIsEnabled() throws {
    var input = TrendTestData.input(cold: true)
    input.preferences.goalMode = .automatic
    let proposal = try XCTUnwrap(TrendCalculator().calculate(input).proposal)
    let workflow = TrendGoalWorkflow { _, _, _, _ in
      XCTFail("Initial goal must be adopted explicitly")
    }
    XCTAssertThrowsError(
      try workflow.adopt(proposalID: proposal.id, input: input, automatically: true))
  }
  func testStaleChangedOrManualInputNeverReachesWriter() throws {
    var input = TrendTestData.input(cold: true)
    let proposal = try XCTUnwrap(TrendCalculator().calculate(input).proposal)
    let workflow = TrendGoalWorkflow { _, _, _, _ in XCTFail("Must not write a stale proposal") }
    input.weights[0].kilograms += 1
    XCTAssertThrowsError(try workflow.adopt(proposalID: proposal.id, input: input))
    input.preferences.goalMode = .manual
    XCTAssertThrowsError(try workflow.adopt(proposalID: proposal.id, input: input))
  }
  func testWriterFailurePropagatesWithoutSeparateHistoryOrGoalWrites() throws {
    let input = TrendTestData.input(cold: true)
    let before = input
    let proposal = try XCTUnwrap(TrendCalculator().calculate(input).proposal)
    var attempts = 0
    let workflow = TrendGoalWorkflow { _, _, _, _ in
      attempts += 1
      throw AnalysisFailure.storageFailed
    }
    XCTAssertThrowsError(try workflow.adopt(proposalID: proposal.id, input: input))
    XCTAssertEqual(attempts, 1)
    XCTAssertEqual(input, before)
  }
  func testUndoRestoresPreviousValuesInNewRevisionAndDisablesAutomaticReapply() throws {
    var input = TrendTestData.input()
    input.preferences.goalMode = .automatic
    let original = input.goalHistory[0]
    var revision = original
    revision.id = AnalysisFixtures.id(2010)
    revision.proposalID = "new-proposal"
    revision.targets = TrendTestData.targets(2400)
    revision.effectiveAt = TrendTestData.calendar.start(input.asOf)
    revision.createdAt = input.asOf
    input.goalHistory.append(revision)
    input.currentManualTargets = revision.targets
    var writes = 0
    let workflow = TrendGoalWorkflow { restored, expected, latest, preferences in
      writes += 1
      XCTAssertEqual(expected, revision.targets)
      XCTAssertEqual(latest, revision.id)
      XCTAssertEqual(restored.targets, original.targets)
      XCTAssertEqual(restored.reversesRevisionID, revision.id)
      XCTAssertEqual(preferences?.goalMode, .suggested)
      XCTAssertEqual(
        preferences?.pausedUntil,
        TrendTestData.calendar.adding(days: 7, to: TrendTestData.calendar.start(input.asOf)))
    }
    let restored = try workflow.undo(revisionID: revision.id, input: input)
    XCTAssertEqual(writes, 1)
    input.goalHistory.append(restored)
    XCTAssertEqual(TrendHistory.ordered(input.goalHistory).last?.id, restored.id)
    XCTAssertThrowsError(
      try workflow.adopt(proposalID: "new-proposal", input: input, automatically: true))
    XCTAssertThrowsError(try workflow.undo(revisionID: revision.id, input: input))
    XCTAssertEqual(writes, 1)
    XCTAssertEqual(input.goalHistory[0], original)
  }
  func testManualWeightAndDietConfirmationRoundTripAndEditInvalidates() throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let repository = SwiftDataAnalysisRepository(container: container)
    let model = TrendViewModel(
      repository: repository, now: { TrendTestData.now },
      timeZone: { TimeZone(secondsFromGMT: 0)! })
    model.reload()
    model.saveWeight(date: TrendTestData.date(0), kilograms: 70)
    XCTAssertNil(model.errorMessage)
    let first = try XCTUnwrap(model.records.weights.first)
    model.saveWeight(id: first.id, date: first.measuredAt, kilograms: 71)
    XCTAssertEqual(model.records.weights.count, 1)
    XCTAssertEqual(model.input?.weights.first?.source, .manual)
    XCTAssertEqual(model.input?.weights.first?.kilograms, 71)
    model.deleteWeight(first.id)
    XCTAssertTrue(model.records.weights.isEmpty)

    let context = ModelContext(container)
    let food = FoodLogEntry(
      loggedAt: TrendTestData.date(0), mealType: .lunch,
      name: "合成午餐", servingDescription: "1 份", quantity: 1,
      calories: 600, carbohydrates: 60, protein: 30, fat: 20)
    context.insert(food)
    try context.save()
    model.reload()
    XCTAssertEqual(model.today?.isComplete, false)
    model.confirmDiet(on: TrendTestData.now)
    XCTAssertEqual(model.today?.isComplete, true)
    food.calories = 610
    try context.save()
    model.reload()
    XCTAssertEqual(model.today?.isComplete, false)
    model.confirmDiet(on: TrendTestData.now)
    XCTAssertEqual(model.today?.isComplete, true)
    XCTAssertEqual(try repository.manualRecords().dietCompleteness.count, 1)
  }
  func testHealthSelectionStoresOnlyReferenceAndDoesNotCreateManualWeight() throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let repository = SwiftDataAnalysisRepository(container: container)
    let health = FixtureHealthDataProvider()
    health.snapshot.samples = [
      .init(
        id: AnalysisFixtures.id(2020), type: .bodyMass,
        start: TrendTestData.date(0), end: TrendTestData.date(0), value: 70, unit: .kilograms,
        source: .init(bundleIdentifier: "fixture.scale", name: "Fixture Scale"))
    ]
    let model = TrendViewModel(
      repository: repository, health: health, now: { TrendTestData.now },
      timeZone: { TimeZone(secondsFromGMT: 0)! })
    model.reload()
    model.selectWeight(try XCTUnwrap(model.input?.weights.first))
    XCTAssertTrue(try repository.manualRecords().weights.isEmpty)
    XCTAssertEqual(try repository.manualRecords().preferences.weightSelections.count, 1)
    XCTAssertEqual(model.input?.weights.first?.isUserSelected, true)
  }
  func testFailedAdoptionPreservesRealRepositoryTargetAndHistory() throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let repository = SwiftDataAnalysisRepository(container: container)
    let fixture = TrendTestData.input(cold: true)
    try repository.saveProfile(try XCTUnwrap(fixture.profile))
    try repository.savePreferences(fixture.preferences)
    for weight in fixture.weights {
      try repository.saveWeight(
        .init(
          id: weight.id, measuredAt: weight.measuredAt, kilograms: weight.kilograms,
          timeZoneIdentifier: "UTC", createdAt: weight.measuredAt, updatedAt: weight.measuredAt))
    }
    let context = ModelContext(container)
    context.insert(NutritionGoal(calories: 2300, carbohydrates: 260, protein: 140, fat: 70))
    try context.save()
    let model = TrendViewModel(
      repository: repository,
      atomicGoalWriter: { _, _, _, _ in
        throw AnalysisFailure.storageFailed
      }, now: { TrendTestData.now }, timeZone: { TimeZone(secondsFromGMT: 0)! })
    model.reload()
    model.adopt(try XCTUnwrap(model.result?.proposal?.id))
    XCTAssertNotNil(model.errorMessage)
    XCTAssertTrue(try repository.manualRecords().goalRevisions.isEmpty)
    XCTAssertEqual(try context.fetch(FetchDescriptor<NutritionGoal>()).first?.calories, 2300)
  }
}
