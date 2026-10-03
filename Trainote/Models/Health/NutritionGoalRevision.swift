import Foundation
import SwiftData

@Model
final class NutritionGoalRevision {
  @Attribute(.unique) var id: UUID
  var effectiveAt: Date
  var calories: Double
  var carbohydrates: Double
  var protein: Double
  var fat: Double
  var originRaw: String
  var proposalID: String?
  var calculationVersion: String?
  var reversesRevisionID: UUID?
  var createdAt: Date

  init(value: NutritionGoalRevisionValue) {
    self.id = value.id
    self.effectiveAt = value.effectiveAt
    self.calories = value.targets.calories
    self.carbohydrates = value.targets.carbohydrates
    self.protein = value.targets.protein
    self.fat = value.targets.fat
    self.originRaw = value.origin.rawValue
    self.proposalID = value.proposalID
    self.calculationVersion = value.calculationVersion
    self.reversesRevisionID = value.reversesRevisionID
    self.createdAt = value.createdAt
  }

  func apply(_ value: NutritionGoalRevisionValue) {
    effectiveAt = value.effectiveAt
    calories = value.targets.calories
    carbohydrates = value.targets.carbohydrates
    protein = value.targets.protein
    fat = value.targets.fat
    originRaw = value.origin.rawValue
    proposalID = value.proposalID
    calculationVersion = value.calculationVersion
    reversesRevisionID = value.reversesRevisionID
    createdAt = value.createdAt
  }

  var value: NutritionGoalRevisionValue {
    .init(
      id: id,
      effectiveAt: effectiveAt,
      targets: .init(calories: calories, carbohydrates: carbohydrates, protein: protein, fat: fat),
      origin: GoalRevisionOrigin(rawValue: originRaw)!,
      proposalID: proposalID,
      calculationVersion: calculationVersion,
      reversesRevisionID: reversesRevisionID,
      createdAt: createdAt)
  }
}
