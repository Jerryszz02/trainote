import Foundation
import Observation

/// F's legacy editor uses the same optimistic transaction as B's proposal workflow.
@MainActor
@Observable
final class ManualNutritionGoalEditing {
  private(set) var expectedState: GoalRevisionState?
  var targets = NutritionTargets(calories: 2_000, carbohydrates: 250, protein: 150, fat: 65)

  func load(from repository: any AnalysisRepository) throws {
    expectedState = nil
    let state = try repository.goalRevisionState()
    expectedState = state
    if let current = state.currentGoal { targets = current.targets }
  }

  func save(to repository: any AnalysisRepository, at date: Date = .now) throws {
    guard let expectedState else { throw GoalRevisionConflict.staleState }
    let revision = NutritionGoalRevisionValue(
      id: UUID(), effectiveAt: date, targets: targets, origin: .manual, createdAt: date)
    do {
      let result = try repository.applyGoalRevision(
        .init(revision: revision, expectedState: expectedState))
      self.expectedState = result.state
    } catch GoalRevisionConflict.staleState {
      // Keep the draft, but require an explicit reload before another save.
      self.expectedState = nil
      throw GoalRevisionConflict.staleState
    }
  }
}
