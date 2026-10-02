import SwiftUI

struct TodayRecoveryCard: View {
  @Environment(\.scenePhase) private var scenePhase
  let integration: HealthRecoveryIntegration
  let hasRoutines: Bool
  let onOpenTemplates: () -> Void
  let onOpenRecovery: () -> Void
  @State private var checkInDraft: CheckInValue?
  @State private var showPrompt = false
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button(
        action: hasRoutines || integration.needsRecoveryReview || integration.failureMessage != nil
          ? onOpenRecovery : onOpenTemplates
      ) {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "lightbulb").font(.title2)
          VStack(alignment: .leading, spacing: 4) {
            Text("今日建议").font(.headline)
            Text(integration.todayMessage(hasRoutines: hasRoutines))
              .font(.subheadline).foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
          Image(systemName: "chevron.right").font(.caption)
        }
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("today.recommendation")
      if integration.healthReadFailed {
        Text("健康数据暂时无法读取，当前显示本地记录。")
          .font(.caption).foregroundStyle(.secondary)
      }
      Divider()
      if showPrompt {
        Text("今天感觉如何？可以用十秒补充体感，也可以跳过。")
          .font(.subheadline).foregroundStyle(.secondary)
          .accessibilityIdentifier("today.checkIn.prompt")
      }
      ViewThatFits(in: .horizontal) {
        HStack {
          checkInButton
          Spacer()
          skipButton
        }
        VStack(alignment: .leading, spacing: 8) {
          checkInButton
          skipButton
        }
      }
    }
    .padding().background(.background, in: RoundedRectangle(cornerRadius: 16))
    .onAppear { reload() }
    .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
    ) {
      _ in reload()
    }
    .sheet(
      item: $checkInDraft,
      onDismiss: {
        integration.reloadToday()
        showPrompt = false
      }
    ) { draft in
      RecoveryCheckInView(
        repository: integration.repository,
        suggestedMuscles: integration.suggestedMuscles(), draft: draft)
    }
    .alert("体感暂时无法打开", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }))
    {
      Button("知道了", role: .cancel) { error = nil }
    } message: {
      Text(error ?? "请稍后重试。")
    }
  }

  private var checkInButton: some View {
    Button("记录或修改十秒体感", systemImage: "heart.text.clipboard") {
      do { checkInDraft = try integration.checkInDraft() } catch { self.error = "未能读取已有体感，请稍后重试。" }
    }
    .font(.subheadline)
    .accessibilityIdentifier("today.checkIn.open")
  }

  @ViewBuilder
  private var skipButton: some View {
    if showPrompt {
      Button("跳过") { showPrompt = false }
        .font(.subheadline)
        .accessibilityIdentifier("today.checkIn.skipPrompt")
    }
  }

  private func reload() {
    integration.reloadToday()
    showPrompt = (try? integration.offerCheckIn()) ?? false
  }
}
