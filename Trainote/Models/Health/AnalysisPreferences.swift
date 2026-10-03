import Foundation
import SwiftData

/// User preferences only. Authorization records and sample values must never enter this model.
@Model
final class AnalysisPreferences {
  static let singletonID = UUID(uuidString: "D1BFF755-887E-46E4-9575-18DCA79B2B98")!
  @Attribute(.unique) var id: UUID
  var goalModeRaw: String
  var pausedUntil: Date?
  var preferredWeightSourceID: String?
  var preferredHealthSourceIDs: [String]
  var weightSelectionsData: Data
  var checkInPromptsEnabled: Bool
  var lastCheckInPromptDate: String?
  var weeklyReviewEnabled: Bool

  init(value: AnalysisPreferencesValue) throws {
    id = Self.singletonID
    goalModeRaw = value.goalMode.rawValue
    pausedUntil = value.pausedUntil
    preferredWeightSourceID = value.preferredWeightSourceID
    preferredHealthSourceIDs = value.preferredHealthSourceIDs
    weightSelectionsData = try JSONEncoder().encode(value.weightSelections)
    checkInPromptsEnabled = value.checkInPromptsEnabled
    lastCheckInPromptDate = value.lastCheckInPromptDate
    weeklyReviewEnabled = value.weeklyReviewEnabled
  }
  func apply(_ value: AnalysisPreferencesValue) throws {
    let selections = try JSONEncoder().encode(value.weightSelections)
    goalModeRaw = value.goalMode.rawValue
    pausedUntil = value.pausedUntil
    preferredWeightSourceID = value.preferredWeightSourceID
    preferredHealthSourceIDs = value.preferredHealthSourceIDs
    weightSelectionsData = selections
    checkInPromptsEnabled = value.checkInPromptsEnabled
    lastCheckInPromptDate = value.lastCheckInPromptDate
    weeklyReviewEnabled = value.weeklyReviewEnabled
  }
  func value() throws -> AnalysisPreferencesValue {
    guard let goalMode = GoalMode(rawValue: goalModeRaw) else { throw AnalysisFailure.invalidInput }
    return .init(
      goalMode: goalMode, pausedUntil: pausedUntil,
      preferredWeightSourceID: preferredWeightSourceID,
      preferredHealthSourceIDs: preferredHealthSourceIDs,
      weightSelections: try JSONDecoder().decode(
        [WeightSelection].self, from: weightSelectionsData),
      checkInPromptsEnabled: checkInPromptsEnabled,
      lastCheckInPromptDate: lastCheckInPromptDate, weeklyReviewEnabled: weeklyReviewEnabled)
  }
}
