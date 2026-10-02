import Foundation

enum MuscleID: String, Codable, CaseIterable, Identifiable, Sendable {
  case chest, back, shoulders, biceps, triceps, forearms, core, glutes, quads, hamstrings, calves
  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .chest: "胸部"
    case .back: "背部"
    case .shoulders: "肩部"
    case .biceps: "肱二头肌"
    case .triceps: "肱三头肌"
    case .forearms: "前臂"
    case .core: "核心"
    case .glutes: "臀部"
    case .quads: "股四头肌"
    case .hamstrings: "腘绳肌"
    case .calves: "小腿"
    }
  }
}


enum RecoveryState: String, Codable, CaseIterable, Sendable {
  case unknown, low, moderate, ready, limited
}

struct BodyMapMuscle: Codable, Equatable, Identifiable, Sendable {
  var muscleID: MuscleID
  var score: Double?
  var state: RecoveryState
  var isSelected: Bool = false
  var hasPain: Bool = false
  var hasMovementLimitation: Bool = false
  var id: MuscleID { muscleID }
}
/// Renderer contract. No formula or thresholds belong in the renderer.
struct BodyMapPresentation: Codable, Equatable, Sendable {
  var muscles: [BodyMapMuscle]
  var asOf: Date
  var calculationVersion: String
  static func unknown(asOf: Date) -> Self {
    Self(muscles: MuscleID.allCases.map { .init(muscleID: $0, score: nil, state: .unknown) },
         asOf: asOf, calculationVersion: "unknown")
  }
}

