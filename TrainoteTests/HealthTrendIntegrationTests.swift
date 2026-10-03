import XCTest

@testable import Trainote

@MainActor
final class HealthTrendIntegrationTests: XCTestCase {
  func testOpeningDoesNotChangeModeAndExplicitSuggestionsPreserveTargets() throws {
    let container = try PersistenceController.makeContainer(inMemory: true)
    let goal = NutritionGoal(calories: 1900, carbohydrates: 220, protein: 120, fat: 65)
    container.mainContext.insert(goal)
    try container.mainContext.save()
    let repository = SwiftDataAnalysisRepository(container: container)
    let defaults = UserDefaults(suiteName: "trend-integration-\(UUID().uuidString)")!
    let integration = HealthTrendIntegration(
      repository: repository, health: nil, defaults: defaults)
    integration.model.reload(allowAutomaticAdoption: false)
    XCTAssertFalse(integration.isEnabled)
    XCTAssertEqual(try repository.manualRecords().preferences.goalMode, .manual)
    XCTAssertEqual(try repository.goalRevisionState().currentGoal?.targets.calories, 1900)
    integration.enableWeeklySuggestions()
    XCTAssertTrue(integration.isEnabled)
    XCTAssertEqual(try repository.manualRecords().preferences.goalMode, .suggested)
    XCTAssertEqual(try repository.goalRevisionState().currentGoal?.id, goal.id)
    XCTAssertEqual(try repository.goalRevisionState().currentGoal?.targets.calories, 1900)
    XCTAssertTrue(try repository.manualRecords().goalRevisions.isEmpty)
    let reopened = HealthTrendIntegration(repository: repository, health: nil, defaults: defaults)
    XCTAssertTrue(reopened.isEnabled)
  }

  func testViewingOnlyKeepsThePersistedModeAndDoesNotGrantHealthConsent() throws {
    let repository = SwiftDataAnalysisRepository(
      container: try PersistenceController.makeContainer(inMemory: true))
    let health = FixtureHealthDataProvider(scenario: .manualOnly)
    let integration = HealthTrendIntegration(
      repository: repository, health: health,
      defaults: UserDefaults(suiteName: "trend-integration-\(UUID().uuidString)")!)
    integration.enterWithoutChangingMode()
    integration.refreshAfterHealthSync()
    XCTAssertTrue(integration.isEnabled)
    XCTAssertEqual(try repository.manualRecords().preferences.goalMode, .manual)
    XCTAssertTrue(try repository.manualRecords().goalRevisions.isEmpty)
    XCTAssertEqual(health.authorizationRequests, 0)
    XCTAssertEqual(health.freshRequests, 0)
  }
}
