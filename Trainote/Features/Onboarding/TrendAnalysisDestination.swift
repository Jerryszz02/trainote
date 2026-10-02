import SwiftUI

private enum TrendIntegrationSheet: String, Identifiable {
  case manualGoal, help
  var id: String { rawValue }
}

struct TrendAnalysisDestination: View {
  @Environment(\.scenePhase) private var scenePhase
  let integration: HealthTrendIntegration
  @State private var sheet: TrendIntegrationSheet?

  var body: some View {
    Group {
      if integration.isEnabled {
        TrendView(
          model: integration.model, onOpenManualGoal: { sheet = .manualGoal },
          onOpenHelp: { sheet = .help })
      } else {
        List {
          Section {
            Text("用体重趋势复核营养目标").font(.title2.bold())
            Text("先积累体重与完整饮食记录，再查看每周建议。已有手动目标会保留，建议只有经过你采用才会生效。")
            Text("身体资料和体重可以稍后填写；Apple 健康与 AI 均可不启用。")
              .foregroundStyle(.secondary)
          }
          Section {
            Button("启用每周建议") { integration.enableWeeklySuggestions() }
              .accessibilityIdentifier("trend.enableSuggestions")
            Button("保留原模式并查看趋势") { integration.enterWithoutChangingMode() }
              .accessibilityIdentifier("trend.continueCurrentMode")
            Button("计算方法与数据使用") { sheet = .help }
          }
          if let error = integration.model.errorMessage {
            Section { Text(error).foregroundStyle(.red) }
          }
        }
        .navigationTitle("趋势分析")
        .onAppear { integration.model.reload(allowAutomaticAdoption: false) }
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { integration.refreshAfterHealthSync() }
    }
    .sheet(
      item: $sheet,
      onDismiss: {
        integration.model.reload(allowAutomaticAdoption: false)
      }
    ) { destination in
      NavigationStack {
        Group {
          switch destination {
          case .manualGoal: NutritionGoalEditor()
          case .help: HealthHelpView()
          }
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("完成") { sheet = nil } }
        }
      }
    }
  }
}
