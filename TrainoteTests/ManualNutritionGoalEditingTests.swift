import SwiftData
import XCTest

@testable import Trainote

@MainActor
final class ManualNutritionGoalEditingTests: XCTestCase {
  private let date = AnalysisFixtures.asOf

  func testLegacyEditorPreservesOldTargetBaselineAndDoesNotChangeMode() throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let old = NutritionGoal(
      calories: 1900, carbohydrates: 200, protein: 120, fat: 60, updatedAt: date)
    container.mainContext.insert(old)
    try container.mainContext.save()
    let repository = SwiftDataAnalysisRepository(container: container)
    try repository.savePreferences(.init(goalMode: .suggested))
    let editing = ManualNutritionGoalEditing()
    try editing.load(from: repository)
    XCTAssertEqual(editing.targets.calories, 1900)
    editing.targets.calories = 2100
    try editing.save(to: repository, at: date.addingTimeInterval(1))
    let state = try repository.goalRevisionState()
    XCTAssertEqual(state.currentGoal?.id, old.id)
    XCTAssertEqual(state.currentGoal?.targets.calories, 2100)
    let records = try repository.manualRecords()
    XCTAssertEqual(records.goalRevisions.count, 2)
    XCTAssertTrue(records.goalRevisions.contains { $0.targets.calories == 1900 })
    XCTAssertEqual(records.preferences.goalMode, .suggested)
    XCTAssertEqual(editing.expectedState, state)
  }

  func testStaleDraftDoesNotOverwriteAndRequiresReloadThenExplicitSave() throws {
    let repository = SwiftDataAnalysisRepository(
      container: try PersistenceController.makeContainer(inMemory: true))
    let first = ManualNutritionGoalEditing()
    let second = ManualNutritionGoalEditing()
    try first.load(from: repository)
    try second.load(from: repository)
    first.targets.calories = 2200
    try first.save(to: repository, at: date)
    second.targets.calories = 1800
    XCTAssertThrowsError(try second.save(to: repository, at: date.addingTimeInterval(1))) {
      XCTAssertEqual($0 as? GoalRevisionConflict, .staleState)
    }
    XCTAssertNil(second.expectedState)
    XCTAssertEqual(second.targets.calories, 1800)
    XCTAssertEqual(try repository.goalRevisionState().currentGoal?.targets.calories, 2200)
    XCTAssertEqual(try repository.manualRecords().goalRevisions.count, 1)
    try second.load(from: repository)
    XCTAssertEqual(second.targets.calories, 2200)
    second.targets.calories = 2050
    try second.save(to: repository, at: date.addingTimeInterval(2))
    XCTAssertEqual(try repository.goalRevisionState().currentGoal?.targets.calories, 2050)
    XCTAssertEqual(try repository.manualRecords().goalRevisions.count, 2)
  }

  func testInvalidTargetKeepsBothCurrentAndHistoryAndDraftForCorrection() throws {
    let repository = SwiftDataAnalysisRepository(
      container: try PersistenceController.makeContainer(inMemory: true))
    let editing = ManualNutritionGoalEditing()
    try editing.load(from: repository)
    try editing.save(to: repository, at: date)
    let original = try repository.goalRevisionState()
    editing.targets.calories = -1
    XCTAssertThrowsError(try editing.save(to: repository, at: date.addingTimeInterval(1)))
    XCTAssertEqual(try repository.goalRevisionState(), original)
    XCTAssertEqual(editing.targets.calories, -1)
    XCTAssertEqual(try repository.manualRecords().goalRevisions.count, 1)
  }
}
