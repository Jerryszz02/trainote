import SwiftUI

/// F supplies verified module views during integration.
/// The default does not install fixture calculators or synthetic health records.
struct HealthAnalysisDestinations {
  var trends: () -> AnyView
  var recovery: (@escaping (Workout) -> Void, @escaping () -> Void) -> AnyView

  static let pending = Self(
    trends: { AnyView(PendingAnalysisView(title: L10n.text("health.healthanalysisdestinations.trend.analysis.cc7a87"), systemImage: "chart.xyaxis.line")) },
    recovery: { _, _ in AnyView(PendingAnalysisView(title: L10n.text("health.healthanalysisdestinations.recovery.analysis.c172e5"), systemImage: "figure.stand")) }
  )

  static func verifiedModules(
    trend: HealthTrendIntegration, recovery: HealthRecoveryIntegration,
    advice: TrainingAdviceController
  ) -> Self {
    Self(
      trends: { AnyView(TrendAnalysisDestination(integration: trend)) },
      recovery: { onStartWorkout, onOpenNutrition in
        AnyView(
          RecoveryAnalysisDestination(
            integration: recovery, advice: advice,
            onStartWorkout: onStartWorkout, onOpenNutrition: onOpenNutrition))
      })
  }
}

private struct PendingAnalysisView: View {
  let title: String
  let systemImage: String
  var body: some View {
    List {
      ContentUnavailableView(
        title, systemImage: systemImage,
        description: Text(L10n.text("health.healthanalysisdestinations.this.feature.is.not.yet.available.4cf963")))
      NavigationLink(L10n.text("health.healthanalysisdestinations.methods.and.data.use.93b2bb")) { HealthHelpView() }
    }
    .navigationTitle(title)
  }
}
