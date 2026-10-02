import Foundation
import SwiftData

@Model
final class DietLogCompleteness {
  @Attribute(.unique) var id: UUID
  var localDate: String
  var timeZoneIdentifier: String
  var confirmedAt: Date
  var foodLogFingerprint: String

  init(value: DietCompletenessValue) {
    self.id = value.id
    self.localDate = value.localDate
    self.timeZoneIdentifier = value.timeZoneIdentifier
    self.confirmedAt = value.confirmedAt
    self.foodLogFingerprint = value.foodLogFingerprint
  }

  func apply(_ value: DietCompletenessValue) {
    localDate = value.localDate
    timeZoneIdentifier = value.timeZoneIdentifier
    confirmedAt = value.confirmedAt
    foodLogFingerprint = value.foodLogFingerprint
  }

  var value: DietCompletenessValue {
    .init(
      id: id,
      localDate: localDate,
      timeZoneIdentifier: timeZoneIdentifier,
      confirmedAt: confirmedAt,
      foodLogFingerprint: foodLogFingerprint)
  }
}
