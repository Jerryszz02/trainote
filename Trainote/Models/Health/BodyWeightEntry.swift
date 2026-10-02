import Foundation
import SwiftData

@Model
final class BodyWeightEntry {
  @Attribute(.unique) var id: UUID
  var measuredAt: Date
  var kilograms: Double
  var timeZoneIdentifier: String
  var createdAt: Date
  var updatedAt: Date

  init(value: ManualWeightValue) {
    self.id = value.id
    self.measuredAt = value.measuredAt
    self.kilograms = value.kilograms
    self.timeZoneIdentifier = value.timeZoneIdentifier
    self.createdAt = value.createdAt
    self.updatedAt = value.updatedAt
  }

  func apply(_ value: ManualWeightValue) {
    measuredAt = value.measuredAt
    kilograms = value.kilograms
    timeZoneIdentifier = value.timeZoneIdentifier
    createdAt = value.createdAt
    updatedAt = value.updatedAt
  }

  var value: ManualWeightValue {
    .init(
      id: id,
      measuredAt: measuredAt,
      kilograms: kilograms,
      timeZoneIdentifier: timeZoneIdentifier,
      createdAt: createdAt,
      updatedAt: updatedAt)
  }
}
