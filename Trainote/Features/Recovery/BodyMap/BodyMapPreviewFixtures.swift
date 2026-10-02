#if DEBUG
  import SwiftUI

  /// Synthetic display values only. These are not outputs of a recovery model.
  enum BodyMapPreviewFixtures {
    static let mixed = BodyMapPresentation(
      muscles: [
        .init(muscleID: .chest, score: 83, state: .ready),
        .init(muscleID: .back, score: nil, state: .unknown),
        .init(muscleID: .shoulders, score: 54, state: .moderate),
        .init(muscleID: .biceps, score: 72, state: .moderate),
        .init(muscleID: .triceps, score: 42, state: .low),
        .init(muscleID: .forearms, score: 92, state: .ready),
        .init(muscleID: .core, score: 65, state: .moderate),
        .init(muscleID: .glutes, score: 24, state: .low),
        .init(muscleID: .quads, score: 31, state: .low),
        .init(muscleID: .hamstrings, score: 47, state: .low),
        .init(muscleID: .calves, score: 0, state: .low),
      ], asOf: Date(timeIntervalSince1970: 1_791_072_000),
      calculationVersion: "body-map-synthetic-v1")
    static let unknown = BodyMapPresentation.unknown(
      asOf: Date(timeIntervalSince1970: 1_791_072_000))
    static let zero = BodyMapPresentation(
      muscles: MuscleID.allCases.map {
        .init(muscleID: $0, score: 0, state: .low)
      }, asOf: Date(timeIntervalSince1970: 1_791_072_000),
      calculationVersion: "body-map-synthetic-zero")
  }

  #Preview("3D · 合成数据") {
    ScrollView {
      BodyMapView(presentation: BodyMapPreviewFixtures.mixed, onSelect: { _ in }).padding()
    }
  }

  #Preview("3D · 待建立记录") {
    ScrollView {
      BodyMapView(presentation: BodyMapPreviewFixtures.unknown, onSelect: { _ in }).padding()
    }
  }

  #Preview("肌群列表 · 辅助功能") {
    ScrollView {
      BodyMapView(
        presentation: BodyMapPreviewFixtures.mixed, onSelect: { _ in }, constrainedPolicy: .list
      )
      .padding()
    }
    .dynamicTypeSize(.accessibility2)
  }
#endif
