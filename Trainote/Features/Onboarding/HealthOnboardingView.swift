import SwiftUI

struct HealthOnboardingView: View {
  @Environment(HealthFeatureAccess.self) private var access
  let onContinue: () -> Void

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("记录照常，分析由你选择")
            .font(.title2.bold())
          Text("训练、饮食和备份可以仅在本机使用。下面两项分别选择，跳过后仍可在设置中开启。")
        }
        Section("Apple 健康") {
          Text("读取你选择共享的体重、睡眠、静息心率、HRV、步数、活动能量和训练，用于本机分析。不向 Apple 健康写入。")
          LabeledContent("读取状态", value: access.healthConnectionLabel)
          if access.healthConnected {
            Text("管理权限：在“健康”App 的摘要中点头像 → App → Trainote。")
              .font(.footnote).foregroundStyle(.secondary)
          }
          Button(access.healthConnected ? "刷新健康读取" : "连接 Apple 健康") {
            Task { await access.connectHealth() }
          }
          .accessibilityIdentifier("health.connect")
          .disabled(access.isBusy || access.health == nil)
        }
        Section("AI 报告") {
          NavigationLink {
            AIConsentView()
          } label: {
            Label("了解并选择 AI 报告", systemImage: "text.bubble")
          }
          .accessibilityIdentifier("health.aiInfo")
          if !access.reports.isConfigured {
            Text(access.reports.configurationMessage).font(.footnote).foregroundStyle(.secondary)
          }
        }
        Section {
          NavigationLink("查看方法、隐私与数据使用") { HealthHelpView() }
            .accessibilityIdentifier("health.help")
          Button(access.healthConnected || access.aiEnabled ? "继续使用 Trainote" : "暂时仅本地使用") {
            onContinue()
          }
          .font(.headline)
          .accessibilityIdentifier("health.localOnly")
          .disabled(access.isBusy)
        }
        if let message = access.statusMessage {
          Section { Text(message).font(.footnote) }
        }
      }
      .navigationTitle("欢迎使用 Trainote")
      .navigationBarTitleDisplayMode(.inline)
      .healthAccessError(access)
    }
    .interactiveDismissDisabled()
  }
}

struct AIConsentView: View {
  var body: some View {
    HealthHelpView(topic: .ai, requestsAIConsent: true)
  }
}

extension View {
  func healthAccessError(_ access: HealthFeatureAccess) -> some View {
    alert(
      "操作未完成",
      isPresented: Binding(
        get: { access.errorMessage != nil }, set: { if !$0 { access.clearError() } }
      )
    ) {
      Button("知道了", role: .cancel) { access.clearError() }
    } message: {
      Text(access.errorMessage ?? "请重试。")
    }
  }
}
