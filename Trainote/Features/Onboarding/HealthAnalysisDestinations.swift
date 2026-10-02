import SwiftUI

/// F supplies verified module views during integration.
/// The default does not install fixture calculators or synthetic health records.
struct HealthAnalysisDestinations {
  var trends: () -> AnyView
  var recovery: () -> AnyView

  static let pending = Self(
    trends: { AnyView(PendingAnalysisView(title: "趋势分析", systemImage: "chart.xyaxis.line")) },
    recovery: { AnyView(PendingAnalysisView(title: "恢复分析", systemImage: "figure.stand")) }
  )

  static func recoveryReady(_ integration: HealthRecoveryIntegration) -> Self {
    Self(trends: pending.trends, recovery: { AnyView(RecoveryAnalysisDestination(integration: integration)) })
  }
}

private struct PendingAnalysisView: View {
  let title: String
  let systemImage: String
  var body: some View {
    List {
      ContentUnavailableView(
        title, systemImage: systemImage,
        description: Text("此功能尚未开放。训练和饮食记录可以照常使用。"))
      NavigationLink("方法与数据使用") { HealthHelpView() }
    }
    .navigationTitle(title)
  }
}
