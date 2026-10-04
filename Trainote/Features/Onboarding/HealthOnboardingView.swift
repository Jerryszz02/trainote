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
  @Environment(HealthFeatureAccess.self) private var access

  var body: some View {
    List {
      Section("可选的第三方处理") {
        Text(
          "AI 报告用于解释本地计算结果和已允许的建议。启用后，必要的训练、饮食、体重和健康趋势汇总会通过代理交由 DeepSeek 处理。Apple 健康连接不代表同意向第三方发送。")
        Text("报告输入不包含姓名、联系方式、自由文本备注、精确位置或完整原始心率序列。AI 不能修改目标或训练历史。")
      }
      Section("当前状态") {
        if access.reports.isConfigured {
          Text("启用前请阅读此版本的处理说明。关闭后停止后续发送与重试，已发送的数据不因取消请求而自动从第三方删除。")
          Button("同意上述处理并启用 AI 报告") { Task { await access.enableAI() } }
            .disabled(access.isBusy || access.aiEnabled)
            .accessibilityIdentifier("health.aiConsent")
        } else {
          Text(access.reports.configurationMessage)
            .accessibilityIdentifier("health.aiUnavailable")
          Text("当前不会向 DeepSeek 发送记录，也不会预先保存 AI 同意。")
        }
      }
      Section { NavigationLink("完整方法与隐私说明") { HealthHelpView() } }
    }
    .navigationTitle("AI 报告")
    .navigationBarTitleDisplayMode(.inline)
    .healthAccessError(access)
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
