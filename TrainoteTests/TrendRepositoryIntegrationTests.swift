import SwiftData
import XCTest

@testable import Trainote

@MainActor
final class TrendRepositoryIntegrationTests: XCTestCase {
  func testCommittedWeightWithRefreshFailureDoesNotBecomeAnotherNewRecord() throws {
    let repository = SwiftDataAnalysisRepository(container: try makeContainer(includeLegacy: false))
    let health = TrendFailingReadProvider()
    let model = TrendViewModel(
      repository: repository, health: health,
      now: { TrendTestData.now }, timeZone: { TimeZone(secondsFromGMT: 0)! })
    model.reload()
    health.failReads = [health.localReads + 1]
    // TrendWeightForm holds this ID for its entire presentation.
    let formID = AnalysisFixtures.id(2810)
    XCTAssertTrue(
      model.saveWeight(id: formID, date: TrendTestData.date(0, hour: 10), kilograms: 71))
    XCTAssertTrue(model.errorMessage?.contains("已保存") == true)
    XCTAssertFalse(model.canApplyGoals)
    XCTAssertEqual(try repository.manualRecords().weights.filter { $0.id == formID }.count, 1)
    XCTAssertTrue(
      model.saveWeight(id: formID, date: TrendTestData.date(0, hour: 10), kilograms: 71))
    XCTAssertEqual(try repository.manualRecords().weights.filter { $0.id == formID }.count, 1)
    XCTAssertNil(model.errorMessage)
  }

  func testCommittedTargetWithRefreshFailureReportsSuccessAndDisablesStaleProposal() throws {
    let repository = SwiftDataAnalysisRepository(container: try makeContainer())
    let health = TrendFailingReadProvider()
    let model = TrendViewModel(
      repository: repository, health: health,
      now: { TrendTestData.now }, timeZone: { TimeZone(secondsFromGMT: 0)! })
    model.reload()
    let proposal = try XCTUnwrap(model.result?.proposal)
    // Preflight succeeds; post-commit display refresh fails.
    health.failReads = [health.localReads + 2]
    XCTAssertTrue(model.adopt(proposal.id))
    XCTAssertTrue(model.errorMessage?.contains("已保存") == true)
    XCTAssertFalse(model.canApplyGoals)
    XCTAssertEqual(try repository.goalRevisionState().currentGoal?.targets, proposal.targets)
    XCTAssertEqual(try repository.manualRecords().goalRevisions.count, 2)
    XCTAssertFalse(model.adopt(proposal.id))
    XCTAssertEqual(try repository.manualRecords().goalRevisions.count, 2)
    model.reload()
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(model.input?.currentManualTargets, proposal.targets)
  }

  func testProfileChangeWaitsSevenDaysAndRequiresExplicitNewBaselineEvenInAutomaticMode() throws {
    let repository = SwiftDataAnalysisRepository(container: try makeContainer(fullHistory: true))
    var clock = TrendTestData.now
    let model = TrendViewModel(
      repository: repository, now: { clock }, timeZone: { TimeZone(secondsFromGMT: 0)! })
    model.reload()
    var profile = try XCTUnwrap(model.input?.profile)
    profile.updatedAt = TrendTestData.date(-1)
    profile.goalDirection = .gain
    XCTAssertTrue(model.saveProfile(profile))
    model.setMode(.automatic)
    let oldState = try repository.goalRevisionState()
    XCTAssertEqual(model.result?.holdReason, .baselineBuilding)
    clock = TrendTestData.calendar.adding(days: 6, to: TrendTestData.now)
    model.reload()
    let proposal = try XCTUnwrap(model.result?.proposal)
    XCTAssertTrue(TrendHistory.needsBaselineRebuild(try XCTUnwrap(model.input)))
    XCTAssertFalse(TrendGoalWorkflow.hasAdoptedBaseline(try XCTUnwrap(model.input)))
    XCTAssertEqual(try repository.goalRevisionState(), oldState)
    XCTAssertTrue(model.adopt(proposal.id))
    let rebuilt = try XCTUnwrap(TrendHistory.baseline(in: XCTUnwrap(model.input)))
    XCTAssertEqual(rebuilt.proposalID, proposal.id)
    XCTAssertEqual(rebuilt.origin, .suggested)
    XCTAssertEqual(rebuilt.targets.calories, 1648.75 * 1.6 * 1.05, accuracy: 1e-8)
    XCTAssertFalse(TrendHistory.needsBaselineRebuild(try XCTUnwrap(model.input)))
    XCTAssertEqual(model.result?.holdReason, .baselineBuilding)
    XCTAssertEqual(model.input?.preferences.goalMode, .automatic)
    clock = TrendTestData.calendar.adding(days: 8, to: clock)
    var later = rebuilt
    later.id = AnalysisFixtures.id(2811)
    later.proposalID = "later-in-new-generation"
    later.targets.calories += 50
    later.effectiveAt = clock
    later.createdAt = clock
    _ = try repository.applyGoalRevision(
      .init(revision: later, expectedState: repository.goalRevisionState()))
    model.reload()
    XCTAssertEqual(TrendHistory.baseline(in: try XCTUnwrap(model.input))?.id, rebuilt.id)
    XCTAssertEqual(try repository.manualRecords().goalRevisions.count, 4)
  }
  func testSameDayAdoptionAndUndoUseOneRepositoryTransactionAndKeepLegacyIdentity() throws {
    let container = try makeContainer()
    let repository = SwiftDataAnalysisRepository(container: container)
    var clock = TrendTestData.now
    let model = TrendViewModel(
      repository: repository, now: { clock }, timeZone: { TimeZone(secondsFromGMT: 0)! })
    model.reload()
    let before = try repository.goalRevisionState()
    let proposal = try XCTUnwrap(model.result?.proposal)
    model.adopt(proposal.id)
    XCTAssertNil(model.errorMessage)
    let adopted = try repository.goalRevisionState()
    XCTAssertEqual(adopted.currentGoal?.id, before.currentGoal?.id)
    XCTAssertEqual(adopted.currentGoal?.targets, proposal.targets)
    XCTAssertEqual(model.records.goalRevisions.count, 2)
    let revision = try XCTUnwrap(model.records.goalRevisions.first { $0.proposalID == proposal.id })
    XCTAssertEqual(revision.effectiveAt, clock)
    XCTAssertEqual(revision.createdAt, clock)
    let baseline = try XCTUnwrap(model.records.goalRevisions.first { $0.origin == .manual })
    XCTAssertEqual(baseline.effectiveAt, before.currentGoal?.updatedAt)
    XCTAssertEqual(baseline.targets, before.currentGoal?.targets)
    XCTAssertNil(
      TrendHistory.effective(at: TrendTestData.date(-1), history: model.records.goalRevisions))
    model.adopt(proposal.id)
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(try repository.goalRevisionState(), adopted)
    XCTAssertEqual(try repository.manualRecords().goalRevisions.count, 2)

    clock.addTimeInterval(60)
    model.reload()
    let preferences = try repository.manualRecords().preferences
    model.undo(revision.id)
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(model.result?.holdReason, .paused)
    let undone = try repository.goalRevisionState()
    XCTAssertEqual(undone.currentGoal?.targets, before.currentGoal?.targets)
    XCTAssertEqual(undone.currentGoal?.id, before.currentGoal?.id)
    XCTAssertEqual(try repository.manualRecords().preferences, preferences)
    XCTAssertEqual(try repository.manualRecords().goalRevisions.count, 3)
    XCTAssertTrue(try repository.manualRecords().goalRevisions.contains { $0 == revision })
    XCTAssertTrue(try repository.manualRecords().goalRevisions.contains { $0 == baseline })
    model.adopt(proposal.id)
    XCTAssertNotNil(model.errorMessage)
    XCTAssertEqual(try repository.goalRevisionState(), undone)
  }

  func testWeeklyAutomaticApplicationIsExplicitAndRunsOnlyOnce() throws {
    let container = try makeContainer(fullHistory: true)
    let repository = SwiftDataAnalysisRepository(container: container)
    let model = TrendViewModel(
      repository: repository, now: { TrendTestData.now }, timeZone: { TimeZone(secondsFromGMT: 0)! }
    )
    model.reload()
    for day in -14 ... -1 { model.confirmDiet(on: TrendTestData.date(day)) }
    XCTAssertNotNil(model.result?.proposal)
    let suggested = try repository.goalRevisionState()
    model.reload()
    XCTAssertEqual(try repository.goalRevisionState(), suggested)
    model.setMode(.automatic)
    model.reload()
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(model.input?.currentManualTargets?.calories, 2200)
    let applied = try repository.goalRevisionState()
    let revision = try XCTUnwrap(
      model.records.goalRevisions.first { $0.id == applied.latestRevisionID })
    XCTAssertEqual(revision.origin, .automatic)
    XCTAssertEqual(revision.targets.calories, 2200)
    model.reload()
    XCTAssertEqual(try repository.goalRevisionState(), applied)
    XCTAssertEqual(model.result?.holdReason, .baselineBuilding)
  }

  func testUndoKeepsAutomaticPreferenceButOnlyAllowsANewReviewAfterSevenDays() throws {
    let container = try makeContainer(fullHistory: true)
    let repository = SwiftDataAnalysisRepository(container: container)
    var clock = TrendTestData.now
    let model = TrendViewModel(
      repository: repository, now: { clock }, timeZone: { TimeZone(secondsFromGMT: 0)! })
    model.reload()
    for day in -14 ... -1 { model.confirmDiet(on: TrendTestData.date(day)) }
    model.setMode(.automatic)
    model.reload()
    let applied = try XCTUnwrap(repository.goalRevisionState().latestRevisionID)
    let originalProposal = try XCTUnwrap(
      model.records.goalRevisions.first { $0.id == applied }?.proposalID)
    clock.addTimeInterval(60)
    model.reload()
    XCTAssertTrue(model.undo(applied))
    let undoneState = try repository.goalRevisionState()
    XCTAssertEqual(model.input?.preferences.goalMode, .automatic)
    XCTAssertEqual(model.result?.holdReason, .paused)
    model.reload()
    XCTAssertEqual(try repository.goalRevisionState(), undoneState)
    clock = TrendTestData.calendar.adding(days: 7, to: clock).addingTimeInterval(1)
    for day in 1...7 {
      try repository.saveWeight(
        .init(
          id: AnalysisFixtures.id(3000 + day), measuredAt: TrendTestData.date(day),
          kilograms: 70, timeZoneIdentifier: "UTC", createdAt: clock, updatedAt: clock))
    }
    let context = ModelContext(container)
    let targets = TrendTestData.targets()
    for day in 0...6 {
      context.insert(
        FoodLogEntry(
          loggedAt: TrendTestData.date(day), mealType: .lunch,
          name: "合成完整饮食", servingDescription: "1 天", quantity: 1,
          calories: targets.calories, carbohydrates: targets.carbohydrates,
          protein: targets.protein, fat: targets.fat))
    }
    try context.save()
    model.reload(allowAutomaticAdoption: false)
    for day in 0...6 { model.confirmDiet(on: TrendTestData.date(day)) }
    let nextProposal = try XCTUnwrap(model.result?.proposal?.id)
    XCTAssertNotEqual(nextProposal, originalProposal)
    model.reload()
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(model.input?.currentManualTargets?.calories, 2200)
    XCTAssertEqual(model.input?.preferences.goalMode, .automatic)
    XCTAssertEqual(
      model.records.goalRevisions.filter { $0.proposalID == originalProposal }.count, 1)
    XCTAssertEqual(model.records.goalRevisions.filter { $0.proposalID == nextProposal }.count, 1)
  }

  func testFirstTargetWithoutLegacyValueDoesNotOfferInventedUndo() throws {
    let container = try makeContainer(includeLegacy: false)
    let repository = SwiftDataAnalysisRepository(container: container)
    var clock = TrendTestData.now
    let model = TrendViewModel(
      repository: repository, now: { clock }, timeZone: { TimeZone(secondsFromGMT: 0)! })
    model.reload()
    let proposal = try XCTUnwrap(model.result?.proposal)
    model.adopt(proposal.id)
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(model.records.goalRevisions.count, 1)
    let revision = try XCTUnwrap(model.records.goalRevisions.first)
    XCTAssertFalse(TrendGoalWorkflow.canUndo(revision.id, input: try XCTUnwrap(model.input)))
    clock.addTimeInterval(1)
    let before = try repository.goalRevisionState()
    model.undo(revision.id)
    XCTAssertNotNil(model.errorMessage)
    XCTAssertEqual(try repository.goalRevisionState(), before)
  }

  func testActualReadOnlySaveFailurePreservesLegacyAndEmptyHistory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("trend-readonly.store")
    try autoreleasepool { _ = try makeContainer(url: url) }
    let container = try PersistenceController.makeContainer(storeURL: url, allowsSave: false)
    let repository = SwiftDataAnalysisRepository(container: container)
    let model = TrendViewModel(
      repository: repository, now: { TrendTestData.now }, timeZone: { TimeZone(secondsFromGMT: 0)! }
    )
    model.reload()
    let before = try repository.goalRevisionState()
    model.adopt(try XCTUnwrap(model.result?.proposal?.id))
    XCTAssertNotNil(model.errorMessage)
    XCTAssertEqual(try repository.goalRevisionState(), before)
    XCTAssertTrue(try repository.manualRecords().goalRevisions.isEmpty)
  }

  func testConcurrentManualEditRejectsDisplayedProposalWithoutOverwriting() throws {
    let container = try makeContainer()
    let repository = SwiftDataAnalysisRepository(container: container)
    let model = TrendViewModel(
      repository: repository, now: { TrendTestData.now }, timeZone: { TimeZone(secondsFromGMT: 0)! }
    )
    model.reload()
    let proposalID = try XCTUnwrap(model.result?.proposal?.id)
    let manual = NutritionGoalRevisionValue(
      id: AnalysisFixtures.id(2800), effectiveAt: TrendTestData.now.addingTimeInterval(-30),
      targets: TrendTestData.targets(2100), origin: .manual,
      createdAt: TrendTestData.now.addingTimeInterval(-30))
    _ = try repository.applyGoalRevision(
      .init(revision: manual, expectedState: repository.goalRevisionState()))
    let changed = try repository.goalRevisionState()
    model.adopt(proposalID)
    XCTAssertNotNil(model.errorMessage)
    XCTAssertEqual(try repository.goalRevisionState(), changed)
  }

  private func makeContainer(includeLegacy: Bool = true, fullHistory: Bool = false, url: URL? = nil)
    throws -> ModelContainer
  {
    let container = try PersistenceController.makeContainer(inMemory: url == nil, storeURL: url)
    let repository = SwiftDataAnalysisRepository(container: container)
    let fixture = TrendTestData.input(cold: !fullHistory)
    try repository.saveProfile(try XCTUnwrap(fixture.profile))
    try repository.savePreferences(fixture.preferences)
    for sample in fixture.weights {
      try repository.saveWeight(
        .init(
          id: sample.id, measuredAt: sample.measuredAt, kilograms: sample.kilograms,
          timeZoneIdentifier: "UTC", createdAt: sample.measuredAt, updatedAt: sample.measuredAt))
    }
    let context = ModelContext(container)
    let targets = TrendTestData.targets()
    if includeLegacy {
      context.insert(
        NutritionGoal(
          calories: targets.calories, carbohydrates: targets.carbohydrates,
          protein: targets.protein, fat: targets.fat,
          updatedAt: fullHistory
            ? TrendTestData.date(-70) : TrendTestData.now.addingTimeInterval(-3600)))
    }
    if fullHistory {
      for day in -14 ... -1 {
        context.insert(
          FoodLogEntry(
            loggedAt: TrendTestData.date(day), mealType: .lunch,
            name: "合成全天饮食", servingDescription: "1 天", quantity: 1,
            calories: targets.calories, carbohydrates: targets.carbohydrates,
            protein: targets.protein, fat: targets.fat))
      }
    }
    try context.save()
    if fullHistory {
      _ = try repository.applyGoalRevision(
        .init(revision: fixture.goalHistory[0], expectedState: repository.goalRevisionState()))
    }
    return container
  }
}

@MainActor
private final class TrendFailingReadProvider: HealthDataProviding {
  var localReads = 0
  var failReads: Set<Int> = []
  func requestReadAuthorization() async throws {}
  func startObserving() async throws {}
  func refresh() async throws {}
  func disconnectAndDelete() async throws {}
  func localSnapshot(window: AnalysisWindow) throws -> HealthDataSnapshot {
    localReads += 1
    if failReads.contains(localReads) { throw AnalysisFailure.readFailed }
    return .disconnected(window: window, asOf: TrendTestData.now)
  }
  func freshSnapshot(window: AnalysisWindow, timeZone: TimeZone) async throws -> HealthDataSnapshot
  {
    try localSnapshot(window: window)
  }
}
