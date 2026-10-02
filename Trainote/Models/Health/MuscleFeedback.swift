import Foundation
import SwiftData

@Model
final class MuscleFeedback {
  @Attribute(.unique) var id: UUID
  var muscleIDRaw: String
  var sorenessRaw: String?
  var hasPain: Bool?
  var hasMovementLimitation: Bool?
  var recordedAt: Date
  var checkIn: DailyCheckIn?

  init(value: MuscleFeedbackValue) {
    self.id = value.id
    self.muscleIDRaw = value.muscleID.rawValue
    self.sorenessRaw = value.soreness?.rawValue
    self.hasPain = value.hasPain
    self.hasMovementLimitation = value.hasMovementLimitation
    self.recordedAt = value.recordedAt
  }

  func apply(_ value: MuscleFeedbackValue) {
    muscleIDRaw = value.muscleID.rawValue
    sorenessRaw = value.soreness?.rawValue
    hasPain = value.hasPain
    hasMovementLimitation = value.hasMovementLimitation
    recordedAt = value.recordedAt
  }

  var value: MuscleFeedbackValue {
    .init(
      id: id,
      muscleID: MuscleID(rawValue: muscleIDRaw)!,
      soreness: sorenessRaw.flatMap(SorenessLevel.init(rawValue:)),
      hasPain: hasPain,
      hasMovementLimitation: hasMovementLimitation,
      recordedAt: recordedAt)
  }
}
