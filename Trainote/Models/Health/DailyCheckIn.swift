import Foundation
import SwiftData

@Model
final class DailyCheckIn {
  @Attribute(.unique) var id: UUID
  var localDate: String
  var timeZoneIdentifier: String
  var feelingRaw: String?
  var sleepFeelingRaw: String?
  var updatedAt: Date
  @Relationship(deleteRule: .cascade, inverse: \MuscleFeedback.checkIn)
  var muscleFeedback: [MuscleFeedback]

  init(value: CheckInValue) {
    id = value.id
    localDate = value.localDate
    timeZoneIdentifier = value.timeZoneIdentifier
    feelingRaw = value.feeling?.rawValue
    sleepFeelingRaw = value.sleepFeeling?.rawValue
    updatedAt = value.updatedAt
    muscleFeedback = value.muscleFeedback.map(MuscleFeedback.init)
  }
  var value: CheckInValue {
    .init(
      id: id, localDate: localDate, timeZoneIdentifier: timeZoneIdentifier,
      feeling: feelingRaw.flatMap(OverallFeeling.init(rawValue:)),
      sleepFeeling: sleepFeelingRaw.flatMap(SleepFeeling.init(rawValue:)),
      muscleFeedback: muscleFeedback.map(\.value).sorted {
        $0.muscleID.rawValue < $1.muscleID.rawValue
      },
      updatedAt: updatedAt)
  }
}
