import SwiftUI

/// Standalone, synthetic-only harness; never registered in the production App target.
@main
struct BodyMapPreviewApp: App {
  var body: some Scene {
    WindowGroup {
      Group {
        if ProcessInfo.processInfo.arguments.contains("-fixture-large-text") {
          BodyMapPreviewRoot().dynamicTypeSize(.accessibility3)
        } else {
          BodyMapPreviewRoot()
        }
      }
      .preferredColorScheme(
        ProcessInfo.processInfo.arguments.contains("-fixture-dark") ? .dark : nil)
    }
  }
}

private struct BodyMapPreviewRoot: View {
  var body: some View {
    NavigationStack {
      if ProcessInfo.processInfo.arguments.contains("-fixture-navigation") {
        NavigationLink("打开恢复分析") {
          BodyMapPreviewScreen()
        }
        .accessibilityIdentifier("preview.openRecovery")
        .navigationTitle("生命周期验收")
      } else {
        BodyMapPreviewScreen()
      }
    }
  }
}

struct BodyMapPreviewScreen: View {
  @State private var selected: MuscleID?
  @State private var fixture = "mixed"
  @State private var callbackCount = 0
  @State private var performance = "采样中"

  private var input: BodyMapPresentation {
    let values =
      fixture == "unknown"
      ? BodyMapPreviewFixtures.unknown
      : fixture == "zero" ? BodyMapPreviewFixtures.zero : BodyMapPreviewFixtures.mixed
    var presentation = values
    presentation.muscles = values.muscles.map { region in
      var region = region
      region.isSelected = region.muscleID == selected
      return region
    }
    return presentation
  }

  private var policy: BodyMapDisplayPolicy? {
    let args = ProcessInfo.processInfo.arguments
    if args.contains("-fixture-list") { return .list }
    return args.contains("-fixture-economical") ? .economical : nil
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        BodyMapView(
          presentation: input,
          onSelect: {
            selected = $0
            callbackCount += 1
          }, constrainedPolicy: policy)
        VStack(alignment: .leading, spacing: 10) {
          if ProcessInfo.processInfo.arguments.contains("-fixture-benchmark") {
            Text(performance).font(.caption.monospaced())
              .accessibilityIdentifier("preview.performance")
          }
          Text("独立组件预览 · 全部为合成数据").font(.caption).foregroundStyle(Color.primary.opacity(0.75))
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
    .task {
      if ProcessInfo.processInfo.arguments.contains("-fixture-benchmark") {
        try? await Task.sleep(for: .milliseconds(600))
        performance = await BodyMapPerformanceProbe.run()
      }
    }
  }
}
