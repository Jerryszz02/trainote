import Foundation

struct CurrentNutritionGoalSnapshot: Codable, Equatable, Sendable {
  var id: UUID
  var targets: NutritionTargets
  var updatedAt: Date
}

/// Optimistic concurrency token: includes the current legacy target and all immutable history.
struct GoalRevisionState: Codable, Equatable, Sendable {
  var currentGoal: CurrentNutritionGoalSnapshot?
  var latestRevisionID: UUID?
  var historyFingerprint: String
}

struct ApplyGoalRevisionRequest: Codable, Equatable, Sendable {
  var revision: NutritionGoalRevisionValue
  var expectedState: GoalRevisionState
}

struct GoalRevisionApplicationResult: Codable, Equatable, Sendable {
  var state: GoalRevisionState
  var appliedRevisionID: UUID
  var insertedBaselineRevisionID: UUID?
  var wasAlreadyApplied: Bool
}

enum GoalRevisionConflict: String, Error, Codable, Sendable {
  case staleState, revisionIDConflict, duplicateProposal, alreadyReversed
  case invalidReversal, invalidChronology, inconsistentHistory, ambiguousCurrentGoal
}
