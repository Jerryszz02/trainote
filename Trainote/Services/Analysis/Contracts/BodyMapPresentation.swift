import Foundation

enum MuscleID: String, Codable, CaseIterable, Identifiable, Sendable {
  case chest, back, shoulders, biceps, triceps, forearms, core, glutes, quads, hamstrings, calves
  var id: String { rawValue }
  var displayName: String {
    switch self {
    case .chest: L10n.text("domain.chest")
    case .back: L10n.text("domain.back")
    case .shoulders: L10n.text("domain.shoulders")
    case .biceps: L10n.text("domain.biceps")
    case .triceps: L10n.text("domain.triceps")
    case .forearms: L10n.text("domain.forearms")
    case .core: L10n.text("domain.core")
    case .glutes: L10n.text("domain.glutes")
    case .quads: L10n.text("domain.quads")
    case .hamstrings: L10n.text("domain.hamstrings")
    case .calves: L10n.text("domain.calves")
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

