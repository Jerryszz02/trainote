import Foundation
import UIKit

/// Renderer-local IDs. The shared analysis contract is adapted at the component boundary.
enum BodyMapMuscle: String, CaseIterable, Identifiable, Codable {
  case chest, back, shoulders, biceps, triceps, forearms, core, glutes, quads, hamstrings, calves

  var id: String { rawValue }

  var title: String {
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
  let muscle: BodyMapMuscle
  let score: Double?
  let status: String
  var id: BodyMapMuscle { muscle }

  init(muscle: BodyMapMuscle, score: Double?, status: String) {
    self.muscle = muscle
    // Invalid presentation values must never become reassuring colours or trap on Int conversion.
    self.score = score.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
    self.status = self.score == nil ? "待建立记录" : status
  }

  var displayedScore: Int? { score.map { Int(($0 / 5).rounded()) * 5 } }
  var scoreText: String { displayedScore.map { "\($0) 分" } ?? "未知" }
  var accessibilityText: String { "\(muscle.title)，\(scoreText)，\(status)" }

  var color: UIColor {
    guard let score else { return UIColor(red: 0.47, green: 0.53, blue: 0.58, alpha: 1) }
    let low = SIMD3<Double>(0.80, 0.25, 0.20)
    let middle = SIMD3<Double>(0.84, 0.60, 0.20)
    let high = SIMD3<Double>(0.16, 0.60, 0.42)
    let fraction = score < 50 ? score / 50 : (score - 50) / 50
    let rgb = score < 50 ? low + (middle - low) * fraction : middle + (high - middle) * fraction
    return UIColor(red: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1)
  }
}

struct BodyMapRenderInput: Equatable {
  let regions: [BodyMapRegion]
  let selected: BodyMapMuscle?

  init(regions: [BodyMapRegion], selected: BodyMapMuscle? = nil) {
    // A partial DTO still exposes all eleven choices; omitted regions stay unknown.
    self.regions = BodyMapMuscle.allCases.map { muscle in
      regions.first(where: { $0.muscle == muscle })
        ?? BodyMapRegion(muscle: muscle, score: nil, status: "待建立记录")
    }
    self.selected = selected
  }

  subscript(muscle: BodyMapMuscle) -> BodyMapRegion {
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
    { return .list }
    return lowPower || thermalState == .fair ? .economical : .standard
  }

  var framesPerSecond: Int { self == .economical ? 20 : 30 }
}
