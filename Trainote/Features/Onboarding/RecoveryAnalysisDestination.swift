import SwiftUI

/// C owns the page; F supplies production dependencies and the bundled methods destination.
struct RecoveryAnalysisDestination: View {
  let integration: HealthRecoveryIntegration
  let advice: TrainingAdviceController
  let onStartWorkout: (Workout) -> Void
  let onOpenNutrition: () -> Void
  @State private var showMethods = false
  @State private var showAdvice = false

  var body: some View {
    Group {
      if let service = integration.service {
        RecoveryView(
          repository: integration.repository, healthData: integration.healthData,
          calculator: service, onShowMethods: { showMethods = true },
          resetCalibration: { integration.calibration.reset(at: .now) })
      } else {
        ContentUnavailableView(
          L10n.text("health.recoveryanalysisdestination.recovery.analysis.unavailable.ee1a30"), systemImage: "figure.stand",
          description: Text(integration.failureMessage ?? L10n.text("health.recoveryanalysisdestination.try.again.later.existing.records.are.dcd98b"))
        )
        .navigationTitle(L10n.text("health.recoveryanalysisdestination.recovery.analysis.c172e5"))
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(L10n.text("health.recoveryanalysisdestination.training.advice.d3707a")) { showAdvice = true }
          .accessibilityIdentifier("recovery.trainingAdvice")
      }
    }
    .navigationDestination(isPresented: $showAdvice) {
      TrainingAdviceView(
        controller: advice,
        onStartWorkout: { workout in
          showAdvice = false
          onStartWorkout(workout)
        },
        onOpenNutrition: {
          showAdvice = false
          onOpenNutrition()
        },
        onOpenRecovery: { showAdvice = false })
    }
    .sheet(isPresented: $showMethods) {
      NavigationStack {
        HealthHelpView(topic: .recovery)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button(L10n.text("health.recoveryanalysisdestination.done.33246f")) { showMethods = false }
            }
          }
      }
    }
  }
}
