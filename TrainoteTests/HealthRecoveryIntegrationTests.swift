import XCTest

@testable import Trainote

@MainActor
final class HealthRecoveryIntegrationTests: XCTestCase {
  private let now = AnalysisFixtures.asOf

  private func repository() throws -> SwiftDataAnalysisRepository {
    SwiftDataAnalysisRepository(container: try PersistenceController.makeContainer(inMemory: true))
  }

  func testProductionServiceKeepsEmptyMusclesUnknownAndOnlyExposesReviewedMappings() throws {
    let integration = HealthRecoveryIntegration(repository: try repository(), healthData: nil)
    integration.reloadToday(at: now, timeZone: .gmt)
    let result = try XCTUnwrap(integration.todayResult)
    XCTAssertTrue(result.muscles.allSatisfy { $0.score == nil && $0.state == .unknown })
    XCTAssertEqual(integration.reviewedExerciseMuscles.count, 38)
    XCTAssertEqual(
      Set(integration.reviewedExerciseMuscles["0025"] ?? []), [.chest, .triceps, .shoulders])
    XCTAssertTrue(result.calculationVersion.contains(RecoveryParameters.version))
    XCTAssertNil(integration.failureMessage)
  }

  func testBothEntrancesSharePromptAndFreshDraftWithoutSavingSkippedAnswers() throws {
    let repository = try repository()
    let integration = HealthRecoveryIntegration(repository: repository, healthData: nil)
    XCTAssertTrue(try integration.offerCheckIn(at: now, timeZone: .gmt))
    XCTAssertFalse(
      try RecoveryCheckInPrompt.offer(
        repository: repository, records: repository.manualRecords(), date: now, timeZone: .gmt))
    _ = try integration.checkInDraft(at: now, timeZone: .gmt)
    XCTAssertTrue(try repository.manualRecords().checkIns.isEmpty)
    var draft = try integration.checkInDraft(at: now, timeZone: .gmt)
    draft.feeling = .tired
    draft.muscleFeedback = [.init(id: UUID(), muscleID: .chest, hasPain: true, recordedAt: now)]
    try RecoveryCheckInWriter.save(draft, repository: repository, at: now)
    integration.reloadToday(at: now.addingTimeInterval(1), timeZone: .gmt)
    XCTAssertTrue(integration.needsRecoveryReview)
    XCTAssertTrue(integration.todayMessage(hasRoutines: false).contains("疼痛"))
    XCTAssertTrue(integration.suggestedMuscles(at: now).contains(.chest))
    var fresh = try integration.checkInDraft(at: now, timeZone: .gmt)
    XCTAssertEqual(fresh.id, draft.id)
    XCTAssertEqual(fresh.feeling, .tired)
    fresh.feeling = nil
    fresh.muscleFeedback = []
    try RecoveryCheckInWriter.save(fresh, repository: repository, at: now.addingTimeInterval(2))
    integration.reloadToday(at: now.addingTimeInterval(3), timeZone: .gmt)
    XCTAssertFalse(integration.needsRecoveryReview)
    XCTAssertTrue(try integration.checkInDraft(at: now, timeZone: .gmt).muscleFeedback.isEmpty)
    XCTAssertEqual(try repository.manualRecords().checkIns.count, 1)
  }

  func testHealthReadFailureStillLoadsManualFeedbackAndDoesNotReadFreshOrAuthorize() throws {
    let repository = try repository()
    let health = FixtureHealthDataProvider()
    health.failure = .readFailed
    let integration = HealthRecoveryIntegration(repository: repository, healthData: health)
    var draft = try integration.checkInDraft(at: now, timeZone: .gmt)
    draft.feeling = .tired
    try RecoveryCheckInWriter.save(draft, repository: repository, at: now)
    integration.reloadToday(at: now.addingTimeInterval(1), timeZone: .gmt)
    XCTAssertTrue(integration.healthReadFailed)
    XCTAssertTrue(integration.needsRecoveryReview)
    XCTAssertNotNil(integration.todayResult)
    XCTAssertEqual(health.freshRequests, 0)
    XCTAssertEqual(health.authorizationRequests, 0)
  }

  func testMissingMappingDoesNotInstallFixtureButManualCheckInRemainsAvailable() throws {
    let integration = HealthRecoveryIntegration(
      repository: try repository(), healthData: nil, bundle: Bundle(for: Self.self))
    integration.reloadToday(at: now, timeZone: .gmt)
    XCTAssertNil(integration.service)
    XCTAssertNil(integration.todayResult)
    XCTAssertNotNil(integration.failureMessage)
    XCTAssertTrue(integration.reviewedExerciseMuscles.isEmpty)
    XCTAssertNil(try integration.checkInDraft(at: now, timeZone: .gmt).feeling)
  }
}
