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
            Text(L10n.text("health.trendanalysisdestination.review.nutrition.targets.with.weight.trends.bdf157")).font(.title2.bold())
            Text(L10n.text("health.trendanalysisdestination.build.up.weight.and.complete.food.94f135"))
            Text(L10n.text("health.trendanalysisdestination.you.can.add.body.details.and.03fd52"))
              .foregroundStyle(.secondary)
          }
          Section {
            Button(L10n.text("health.trendanalysisdestination.enable.weekly.suggestions.512d36")) { integration.enableWeeklySuggestions() }
              .accessibilityIdentifier("trend.enableSuggestions")
            Button(L10n.text("health.trendanalysisdestination.keep.current.mode.and.view.trends.9e6c54")) { integration.enterWithoutChangingMode() }
              .accessibilityIdentifier("trend.continueCurrentMode")
            Button(L10n.text("health.trendanalysisdestination.methods.and.data.use.df2501")) { sheet = .help }
          }
          if let error = integration.model.errorMessage {
            Section { Text(error).foregroundStyle(.red) }
          }
        }
        .navigationTitle(L10n.text("health.trendanalysisdestination.trend.analysis.cc7a87"))
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
          ToolbarItem(placement: .cancellationAction) { Button(L10n.text("health.trendanalysisdestination.done.33246f")) { sheet = nil } }
        }
      }
    }
  }
}
