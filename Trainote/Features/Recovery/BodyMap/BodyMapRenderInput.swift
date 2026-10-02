import Foundation
import UIKit

/// Compact display names; identity belongs to the frozen analysis contract.
extension MuscleID {
  var bodyMapTitle: String {
    switch self {
    case .chest: "胸"
    case .back: "背"
    case .shoulders: "肩"
    case .biceps: "肱二头"
    case .triceps: "肱三头"
    case .forearms: "前臂"
    case .core: "核心"
    case .glutes: "臀"
    case .quads: "股四头"
    case .hamstrings: "腘绳肌"
    case .calves: "小腿"
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
    self.status = self.score == nil ? (isLimited ? "\(status) · 待建立记录" : "待建立记录") : status
  }

  var displayedScore: Int? { score.map { Int(($0 / 5).rounded()) * 5 } }
  var scoreText: String { displayedScore.map { "\($0) 分" } ?? "未知" }
  var accessibilityText: String { "\(muscle.bodyMapTitle)，\(scoreText)，\(status)" }
  var compactStatus: String {
    isLimited ? status.replacingOccurrences(of: "待建立记录", with: "未知") : status
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
        status = "疼痛/受限"
      } else if value.hasPain {
        status = "疼痛反馈"
      } else if value.hasMovementLimitation {
        status = "活动受限"
      } else {
        status =
          switch value.state {
          case .unknown: "待建立记录"
          case .low: "优先恢复"
          case .moderate: "适度安排"
          case .ready: "状态较好"
          case .limited: "受限"
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
        ?? BodyMapRegion(muscle: muscle, score: nil, status: "待建立记录")
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
