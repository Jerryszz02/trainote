import SwiftUI

/// Standalone, synthetic-only harness; never registered in the production App target.
@main
struct BodyMapPreviewApp: App {
  var body: some Scene {
    WindowGroup { BodyMapPreviewScreen() }
  }
}

struct BodyMapPreviewScreen: View {
  @State private var selected: BodyMapMuscle?
  @State private var fixture = "mixed"
  @State private var callbackCount = 0

  private var input: BodyMapRenderInput {
    let values = fixture == "unknown" ? BodyMapFixtures.unknown
      : fixture == "zero" ? BodyMapFixtures.zero : BodyMapFixtures.mixed
    return BodyMapRenderInput(regions: values.regions, selected: selected)
  }

  private var policy: BodyMapDisplayPolicy? {
    let args = ProcessInfo.processInfo.arguments
    if args.contains("-fixture-list") { return .list }
    return args.contains("-fixture-economical") ? .economical : nil
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          BodyMapRendererView(input: input, onSelect: {
            selected = $0
            callbackCount += 1
          }, constrainedPolicy: policy)
          VStack(alignment: .leading, spacing: 10) {
            Text("独立组件预览 · 全部为合成数据").font(.caption).foregroundStyle(.secondary)
            Picker("固定数据", selection: $fixture) {
              Text("混合状态").tag("mixed")
              Text("全部未知").tag("unknown")
              Text("全部零分").tag("zero")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("preview.fixture")
            Text("选择回调：\(selected?.rawValue ?? "none") · \(callbackCount)")
              .font(.caption.monospaced()).accessibilityIdentifier("preview.callback")
          }
        }
        .padding(16)
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .navigationTitle("恢复分析")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}
