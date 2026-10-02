import SwiftData
import XCTest

@testable import Trainote

@MainActor
final class GoalRevisionTransactionTests: XCTestCase {
  private let before = NutritionTargets(calories: 2000, carbohydrates: 240, protein: 120, fat: 60)
  private let after = NutritionTargets(calories: 2150, carbohydrates: 260, protein: 130, fat: 60)
  private let date = AnalysisFixtures.asOf

  func testFirstAdoptionAtomicallyKeepsBaselineAndLegacyGoalID() throws {
    let container = try makeContainer()
    let repo = SwiftDataAnalysisRepository(container: container)
    let initial = try repo.goalRevisionState()
    let request = ApplyGoalRevisionRequest(revision: adoption(801), expectedState: initial)
    let result = try repo.applyGoalRevision(request)
    XCTAssertFalse(result.wasAlreadyApplied)
    XCTAssertEqual(result.state.currentGoal?.id, initial.currentGoal?.id)
    XCTAssertEqual(result.state.currentGoal?.targets, after)
    XCTAssertEqual(result.state.latestRevisionID, request.revision.id)
    XCTAssertEqual(try repo.goalRevisionState(), result.state)
    let history = try repo.manualRecords().goalRevisions
    XCTAssertEqual(history.count, 2)
    let baseline = try XCTUnwrap(history.first { $0.id == result.insertedBaselineRevisionID })
    XCTAssertEqual(baseline.targets, before)
    XCTAssertEqual(baseline.origin, .manual)
    XCTAssertEqual(baseline.effectiveAt, date)
    XCTAssertEqual(baseline.createdAt, request.revision.createdAt)
    XCTAssertNil(baseline.proposalID)
    XCTAssertEqual(history.first { $0.id == request.revision.id }, request.revision)
    XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<NutritionGoal>()), 1)
    let repeated = try repo.applyGoalRevision(request)  // The original expectedState is deliberately stale.
    XCTAssertTrue(repeated.wasAlreadyApplied)
    XCTAssertEqual(repeated.state, result.state)
    XCTAssertNil(repeated.insertedBaselineRevisionID)
    XCTAssertEqual(try repo.manualRecords().goalRevisions.count, 2)
  }

  func testUndoAppendsHistoryAndExactReplaysNeverReapplyAnOldTarget() throws {
    let container = try makeContainer()
    let repo = SwiftDataAnalysisRepository(container: container)
    let request = ApplyGoalRevisionRequest(
      revision: adoption(802), expectedState: try repo.goalRevisionState())
    let applied = try repo.applyGoalRevision(request)
    let originalHistory = try repo.manualRecords().goalRevisions
    let undo = NutritionGoalRevisionValue(
      id: AnalysisFixtures.id(803), effectiveAt: date.addingTimeInterval(20),
      targets: before, origin: .manual, reversesRevisionID: request.revision.id,
      createdAt: date.addingTimeInterval(20))
    let undoRequest = ApplyGoalRevisionRequest(revision: undo, expectedState: applied.state)
    let undone = try repo.applyGoalRevision(undoRequest)
    XCTAssertEqual(undone.state.currentGoal?.targets, before)
    XCTAssertEqual(undone.state.latestRevisionID, undo.id)
    let history = try repo.manualRecords().goalRevisions
    XCTAssertEqual(history.count, 3)
    for original in originalHistory {
      XCTAssertEqual(history.first { $0.id == original.id }, original)
    }
    XCTAssertEqual(history.first { $0.id == undo.id }?.reversesRevisionID, request.revision.id)
    XCTAssertTrue(try repo.applyGoalRevision(undoRequest).wasAlreadyApplied)
    let oldReplay = try repo.applyGoalRevision(request)
    XCTAssertTrue(oldReplay.wasAlreadyApplied)
    XCTAssertEqual(oldReplay.state.currentGoal?.targets, before)
    XCTAssertEqual(try repo.manualRecords().goalRevisions.count, 3)
    var duplicateUndo = undo
    duplicateUndo.id = UUID()
    XCTAssertThrowsError(
      try repo.applyGoalRevision(.init(revision: duplicateUndo, expectedState: undone.state))
    ) {
      XCTAssertEqual($0 as? GoalRevisionConflict, .alreadyReversed)
    }
  }

  func testStaleStateDuplicateProposalAndRevisionIDConflictDoNotMutateEitherSide() throws {
    let container = try makeContainer()
    let repo = SwiftDataAnalysisRepository(container: container)
    let initial = try repo.goalRevisionState()
    let revision = adoption(804)
    let applied = try repo.applyGoalRevision(.init(revision: revision, expectedState: initial))
    let history = try repo.manualRecords().goalRevisions
    let next = adoption(805, offset: 30)
    XCTAssertThrowsError(try repo.applyGoalRevision(.init(revision: next, expectedState: initial)))
    {
      XCTAssertEqual($0 as? GoalRevisionConflict, .staleState)
    }
    var repeatedProposal = next
    repeatedProposal.proposalID = revision.proposalID
    XCTAssertThrowsError(
      try repo.applyGoalRevision(.init(revision: repeatedProposal, expectedState: applied.state))
    ) {
      XCTAssertEqual($0 as? GoalRevisionConflict, .duplicateProposal)
    }
    var conflictingID = revision
    conflictingID.targets.calories = 2300
    XCTAssertThrowsError(
      try repo.applyGoalRevision(.init(revision: conflictingID, expectedState: applied.state))
    ) {
      XCTAssertEqual($0 as? GoalRevisionConflict, .revisionIDConflict)
    }
    XCTAssertEqual(try repo.goalRevisionState(), applied.state)
    XCTAssertEqual(
      try repo.manualRecords().goalRevisions.sorted { $0.id.uuidString < $1.id.uuidString },
      history.sorted { $0.id.uuidString < $1.id.uuidString })
  }

  func testUndoRejectsInventedTargetsAndSupersededRevision() throws {
    let repo = SwiftDataAnalysisRepository(container: try makeContainer())
    let first = adoption(806)
    let applied = try repo.applyGoalRevision(
      .init(revision: first, expectedState: try repo.goalRevisionState()))
    var badUndo = NutritionGoalRevisionValue(
      id: AnalysisFixtures.id(807), effectiveAt: date.addingTimeInterval(20),
      targets: after, origin: .manual, reversesRevisionID: first.id,
      createdAt: date.addingTimeInterval(20))
    XCTAssertThrowsError(
      try repo.applyGoalRevision(.init(revision: badUndo, expectedState: applied.state))
    ) {
      XCTAssertEqual($0 as? GoalRevisionConflict, .invalidReversal)
    }
    let second = adoption(808, offset: 30)
    let latest = try repo.applyGoalRevision(.init(revision: second, expectedState: applied.state))
    badUndo.targets = before
    badUndo.effectiveAt = date.addingTimeInterval(40)
    badUndo.createdAt = date.addingTimeInterval(40)
    XCTAssertThrowsError(
      try repo.applyGoalRevision(.init(revision: badUndo, expectedState: latest.state))
    ) {
      XCTAssertEqual($0 as? GoalRevisionConflict, .invalidReversal)
    }
    XCTAssertEqual(try repo.goalRevisionState(), latest.state)
  }

  func testManualEditAndAppendedHistoryInvalidateCapturedExpectation() throws {
    let container = try makeContainer()
    let repo = SwiftDataAnalysisRepository(container: container)
    let captured = try repo.goalRevisionState()
    let context = ModelContext(container)
    let manual = try XCTUnwrap(context.fetch(FetchDescriptor<NutritionGoal>()).first)
    manual.calories = 1900
    manual.updatedAt = date.addingTimeInterval(1)
    try context.save()
    XCTAssertThrowsError(
      try repo.applyGoalRevision(.init(revision: adoption(809), expectedState: captured))
    ) {
      XCTAssertEqual($0 as? GoalRevisionConflict, .staleState)
    }
    XCTAssertTrue(try repo.manualRecords().goalRevisions.isEmpty)
    let current = try repo.goalRevisionState()
    try repo.appendGoalRevision(
      .init(id: UUID(), effectiveAt: date, targets: before, origin: .manual, createdAt: date))
    XCTAssertThrowsError(
      try repo.applyGoalRevision(.init(revision: adoption(810), expectedState: current))
    ) {
      XCTAssertEqual($0 as? GoalRevisionConflict, .staleState)
    }
    XCTAssertEqual(try repo.goalRevisionState().currentGoal?.targets.calories, 1900)
  }

  func testFirstGoalWithoutPreviousTargetDoesNotInventBaseline() throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let repo = SwiftDataAnalysisRepository(container: container)
    let result = try repo.applyGoalRevision(
      .init(revision: adoption(811), expectedState: try repo.goalRevisionState()))
    XCTAssertNil(result.insertedBaselineRevisionID)
    XCTAssertEqual(try repo.manualRecords().goalRevisions.count, 1)
    XCTAssertEqual(result.state.currentGoal?.targets, after)
  }

  func testSaveFailureRollsBackLegacyTargetAndBothBaselineAndNewRevision() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("readonly-goals.store")
    try autoreleasepool {
      let writable = try makeContainer(url: url)
      try writable.mainContext.save()
    }
    let container = try PersistenceController.makeContainer(storeURL: url, allowsSave: false)
    let repo = SwiftDataAnalysisRepository(container: container)
    let before = try repo.goalRevisionState()
    XCTAssertThrowsError(
      try repo.applyGoalRevision(.init(revision: adoption(812), expectedState: before)))
    XCTAssertEqual(try repo.goalRevisionState(), before)
    XCTAssertTrue(try repo.manualRecords().goalRevisions.isEmpty)
  }

  private func makeContainer(url: URL? = nil) throws -> ModelContainer {
    let container = try PersistenceController.makeContainer(inMemory: url == nil, storeURL: url)
    let context = ModelContext(container)
    context.insert(
      NutritionGoal(
        id: AnalysisFixtures.id(800), calories: before.calories,
        carbohydrates: before.carbohydrates, protein: before.protein, fat: before.fat,
        updatedAt: date))
    try context.save()
    return container
  }

  private func adoption(_ id: Int, offset: Double = 10) -> NutritionGoalRevisionValue {
    .init(
      id: AnalysisFixtures.id(id), effectiveAt: date.addingTimeInterval(offset), targets: after,
      origin: .suggested, proposalID: "fixture-proposal-\(id)", calculationVersion: "test-v1",
      createdAt: date.addingTimeInterval(offset))
  }
}
