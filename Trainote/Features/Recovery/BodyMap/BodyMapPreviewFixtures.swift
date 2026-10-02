#if DEBUG
  import SwiftUI

  /// Synthetic display values only. These are not outputs of a recovery model.
  enum BodyMapFixtures {
    static let mixed = BodyMapRenderInput(regions: [
      .init(muscle: .chest, score: 83, status: "状态较好"),
      .init(muscle: .back, score: nil, status: "待建立记录"),
      .init(muscle: .shoulders, score: 54, status: "适度安排"),
      .init(muscle: .biceps, score: 72, status: "适度安排"),
      .init(muscle: .triceps, score: 42, status: "优先恢复"),
      .init(muscle: .forearms, score: 92, status: "状态较好"),
      .init(muscle: .core, score: 65, status: "适度安排"),
      .init(muscle: .glutes, score: 24, status: "优先恢复"),
      .init(muscle: .quads, score: 31, status: "优先恢复"),
      .init(muscle: .hamstrings, score: 47, status: "优先恢复"),
      .init(muscle: .calves, score: 0, status: "优先恢复"),
    ])
    static let unknown = BodyMapRenderInput(regions: [])
    static let zero = BodyMapRenderInput(regions: BodyMapMuscle.allCases.map {
      .init(muscle: $0, score: 0, status: "优先恢复")
    })
  }

  #Preview("3D · 合成数据") {
    ScrollView {
      BodyMapRendererView(input: BodyMapFixtures.mixed, onSelect: { _ in }).padding()
    }
  }

  #Preview("3D · 待建立记录") {
    ScrollView {
      BodyMapRendererView(input: BodyMapFixtures.unknown, onSelect: { _ in }).padding()
    }
  }

  #Preview("肌群列表 · 辅助功能") {
    ScrollView {
      BodyMapRendererView(input: BodyMapFixtures.mixed, onSelect: { _ in }, constrainedPolicy: .list)
        .padding()
    }
    .dynamicTypeSize(.accessibility2)
  }
#endif
