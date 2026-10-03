import Foundation
import SwiftData

@Model
final class BodyProfile {
  @Attribute(.unique) var id: UUID
  var isActive: Bool
  var heightCentimeters: Double?
  var birthYear: Int?
  var ageYears: Int?
  var formulaSexRaw: String?
  var activityLevelRaw: String?
  var goalDirectionRaw: String?
  var targetWeeklyChangePercent: Double?
  var trainingDaysPerWeek: Int?
  var bodyFatPercent: Double?
  var waistCentimeters: Double?
  var isAdultGeneralFitness: Bool?
  var updatedAt: Date

  init(value: BodyProfileValue) {
    self.id = value.id
    self.isActive = value.isActive
    self.heightCentimeters = value.heightCentimeters
    self.birthYear = value.birthYear
    self.ageYears = value.ageYears
    self.formulaSexRaw = value.formulaSex?.rawValue
    self.activityLevelRaw = value.activityLevel?.rawValue
    self.goalDirectionRaw = value.goalDirection?.rawValue
    self.targetWeeklyChangePercent = value.targetWeeklyChangePercent
    self.trainingDaysPerWeek = value.trainingDaysPerWeek
    self.bodyFatPercent = value.bodyFatPercent
    self.waistCentimeters = value.waistCentimeters
    self.isAdultGeneralFitness = value.isAdultGeneralFitness
    self.updatedAt = value.updatedAt
  }

  func apply(_ value: BodyProfileValue) {
    isActive = value.isActive
    heightCentimeters = value.heightCentimeters
    birthYear = value.birthYear
    ageYears = value.ageYears
    formulaSexRaw = value.formulaSex?.rawValue
    activityLevelRaw = value.activityLevel?.rawValue
    goalDirectionRaw = value.goalDirection?.rawValue
    targetWeeklyChangePercent = value.targetWeeklyChangePercent
    trainingDaysPerWeek = value.trainingDaysPerWeek
    bodyFatPercent = value.bodyFatPercent
    waistCentimeters = value.waistCentimeters
    isAdultGeneralFitness = value.isAdultGeneralFitness
    updatedAt = value.updatedAt
  }

  var value: BodyProfileValue {
    .init(
      id: id,
      isActive: isActive,
      heightCentimeters: heightCentimeters,
      birthYear: birthYear,
      ageYears: ageYears,
      formulaSex: formulaSexRaw.flatMap(FormulaSex.init(rawValue:)),
      activityLevel: activityLevelRaw.flatMap(ActivityLevel.init(rawValue:)),
      goalDirection: goalDirectionRaw.flatMap(GoalDirection.init(rawValue:)),
      targetWeeklyChangePercent: targetWeeklyChangePercent,
      trainingDaysPerWeek: trainingDaysPerWeek,
      bodyFatPercent: bodyFatPercent,
      waistCentimeters: waistCentimeters,
      isAdultGeneralFitness: isAdultGeneralFitness,
      updatedAt: updatedAt)
  }
}
