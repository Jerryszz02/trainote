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
          "恢复分析暂不可用", systemImage: "figure.stand",
          description: Text(integration.failureMessage ?? "请稍后重试。原有记录仍可使用。")
        )
        .navigationTitle("恢复分析")
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("训练建议") { showAdvice = true }
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
        HealthHelpView()
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("完成") { showMethods = false }
            }
          }
      }
    }
  }
}
