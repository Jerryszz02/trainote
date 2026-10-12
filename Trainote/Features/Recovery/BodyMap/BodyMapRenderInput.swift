import Foundation
import UIKit

/// Compact display names; identity belongs to the frozen analysis contract.
extension MuscleID {
  var bodyMapTitle: String {
    switch self {
    case .chest: L10n.text("health.bodymaprenderinput.chest.a6577e")
    case .back: L10n.text("health.bodymaprenderinput.back.e072ff")
    case .shoulders: L10n.text("health.bodymaprenderinput.shoulders.dd0ea6")
    case .biceps: L10n.text("health.bodymaprenderinput.biceps.9eee82")
    case .triceps: L10n.text("health.bodymaprenderinput.triceps.87f8af")
    case .forearms: L10n.text("health.bodymaprenderinput.forearms.05789a")
    case .core: L10n.text("health.bodymaprenderinput.core.10d95f")
    case .glutes: L10n.text("health.bodymaprenderinput.glutes.447078")
    case .quads: L10n.text("health.bodymaprenderinput.quads.8f5d54")
    case .hamstrings: L10n.text("health.bodymaprenderinput.hamstrings.9218b4")
    case .calves: L10n.text("health.bodymaprenderinput.calves.733e65")
    }
  }
}

struct BodyMapRegion: Equatable, Identifiable {
  let muscle: MuscleID
  let score: Double?
  let status: String
  let isLimited: Bool
  var id: MuscleID { muscle }

  init(muscle: MuscleID, score: Double?, status: String, isLimited: Bool = false) {
    self.muscle = muscle
    self.isLimited = isLimited
    // Invalid presentation values must never become reassuring colours or trap on Int conversion.
    self.score = score.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
    self.status = self.score == nil ? (isLimited ? L10n.text("health.bodymaprenderinput.waiting.for.records.e0d73f", String(status)) : L10n.text("health.bodymaprenderinput.waiting.for.records.dda84c")) : status
  }

  var displayedScore: Int? { score.map { Int(($0 / 5).rounded()) * 5 } }
  var scoreText: String { displayedScore.map { L10n.text("health.bodymaprenderinput.points.af77b9", $0) } ?? L10n.text("health.bodymaprenderinput.unknown.d9c32a") }
  var accessibilityText: String { [muscle.bodyMapTitle, scoreText, status].joined(separator: L10n.language == .english ? ", " : "，") }
  var compactStatus: String {
    isLimited ? status.replacingOccurrences(of: L10n.text("health.bodymaprenderinput.waiting.for.records.dda84c"), with: L10n.text("health.bodymaprenderinput.unknown.d9c32a")) : status
  }

  var color: UIColor {
    if isLimited { return UIColor(red: 0.73, green: 0.39, blue: 0.14, alpha: 1) }
    guard let score else { return UIColor(red: 0.47, green: 0.53, blue: 0.58, alpha: 1) }
    let low = SIMD3<Double>(0.80, 0.25, 0.20)
    let middle = SIMD3<Double>(0.84, 0.60, 0.20)
    let high = SIMD3<Double>(0.16, 0.60, 0.42)
    let fraction = score < 50 ? score / 50 : (score - 50) / 50
    let rgb = score < 50 ? low + (middle - low) * fraction : middle + (high - middle) * fraction
    return UIColor(red: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1)
  }
}

extension BodyMapRenderInput {
  init(presentation: BodyMapPresentation) {
    let regions = presentation.muscles.map { value in
      let limited = value.hasPain || value.hasMovementLimitation || value.state == .limited
      let status: String
      if value.hasPain && value.hasMovementLimitation {
        status = L10n.text("health.bodymaprenderinput.pain.limited.27f305")
      } else if value.hasPain {
        status = L10n.text("health.bodymaprenderinput.pain.reported.508f5b")
      } else if value.hasMovementLimitation {
        status = L10n.text("health.bodymaprenderinput.limited.movement.4b936a")
      } else {
        status =
          switch value.state {
          case .unknown: L10n.text("health.bodymaprenderinput.waiting.for.records.dda84c")
          case .low: L10n.text("health.bodymaprenderinput.prioritize.recovery.41ef55")
          case .moderate: L10n.text("health.bodymaprenderinput.train.moderately.726903")
          case .ready: L10n.text("health.bodymaprenderinput.good.readiness.d4d8e0")
          case .limited: L10n.text("health.bodymaprenderinput.limited.936333")
          }
      }
      return BodyMapRegion(
        muscle: value.muscleID, score: value.state == .unknown ? nil : value.score,
        status: status, isLimited: limited)
    }
    self.init(regions: regions, selected: presentation.muscles.first(where: \.isSelected)?.muscleID)
  }
}

struct BodyMapRenderInput: Equatable {
  let regions: [BodyMapRegion]
  let selected: MuscleID?

  init(regions: [BodyMapRegion], selected: MuscleID? = nil) {
    // A partial DTO still exposes all eleven choices; omitted regions stay unknown.
    self.regions = MuscleID.allCases.map { muscle in
      regions.first(where: { $0.muscle == muscle })
        ?? BodyMapRegion(muscle: muscle, score: nil, status: L10n.text("health.bodymaprenderinput.waiting.for.records.dda84c"))
    }
    self.selected = selected
  }

  subscript(muscle: MuscleID) -> BodyMapRegion {
    regions.first(where: { $0.muscle == muscle })!
  }

  var isEmpty: Bool { regions.allSatisfy { $0.score == nil } }
}

enum BodyMapViewpoint: Equatable {
  case front, back
  var angle: Float { self == .front ? 0 : .pi }
}

/// The decision is also used by the fixture harness; it does not read or change health data.
enum BodyMapDisplayPolicy: Equatable {
  case standard, economical, list

  static func resolve(
    voiceOver: Bool, largeText: Bool, lowPower: Bool, thermalState: ProcessInfo.ThermalState,
    rendererAvailable: Bool
  ) -> Self {
    if voiceOver || largeText || !rendererAvailable || thermalState == .serious
      || thermalState == .critical
    {
      return .list
    }
    return lowPower || thermalState == .fair ? .economical : .standard
  }

  var framesPerSecond: Int { self == .economical ? 20 : 30 }
}
