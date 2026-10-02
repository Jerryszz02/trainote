import SwiftUI

/// C owns the page; F supplies production dependencies and the bundled methods destination.
struct RecoveryAnalysisDestination: View {
  let integration: HealthRecoveryIntegration
  @State private var showMethods = false

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
