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

  #Preview(L10n.text("health.bodymappreviewfixtures.muscle.map.sample.data.7fc611")) {
    ScrollView {
      BodyMapView(presentation: BodyMapPreviewFixtures.mixed, onSelect: { _ in }).padding()
    }
  }

  #Preview(L10n.text("health.bodymappreviewfixtures.muscle.map.waiting.for.records.71559d")) {
    ScrollView {
      BodyMapView(presentation: BodyMapPreviewFixtures.unknown, onSelect: { _ in }).padding()
    }
  }

  #Preview(L10n.text("health.bodymappreviewfixtures.muscle.list.accessibility.4fe303")) {
    ScrollView {
      BodyMapView(
        presentation: BodyMapPreviewFixtures.mixed, onSelect: { _ in }, constrainedPolicy: .list
      )
      .padding()
    }
    .dynamicTypeSize(.accessibility2)
  }
#endif
