import SwiftUI

struct HealthOnboardingView: View {
  @Environment(HealthFeatureAccess.self) private var access
  let onContinue: () -> Void

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text(L10n.text("health.healthonboardingview.keep.recording.choose.your.analysis.cc9165"))
            .font(.title2.bold())
          Text(L10n.text("health.healthonboardingview.workouts.food.and.backups.can.stay.3ab8ec"))
        }
        Section(L10n.text("health.healthonboardingview.apple.health.6de270")) {
          Text(L10n.text("health.healthonboardingview.read.the.weight.sleep.resting.heart.6bba43"))
          LabeledContent(L10n.text("health.healthonboardingview.read.status.48e33e"), value: access.healthConnectionLabel)
          if access.healthConnected {
            Text(L10n.text("health.healthonboardingview.manage.access.in.health.tap.summary.fc8c28"))
              .font(.footnote).foregroundStyle(.secondary)
          }
          Button(access.healthConnected ? L10n.text("health.healthonboardingview.refresh.health.data.a1d25f") : L10n.text("health.healthonboardingview.connect.apple.health.eb4d4c")) {
            Task { await access.connectHealth() }
          }
          .accessibilityIdentifier("health.connect")
          .disabled(access.isBusy || access.health == nil)
        }
        Section(L10n.text("health.healthonboardingview.ai.reports.9885c1")) {
          NavigationLink {
            AIConsentView()
          } label: {
            Label(L10n.text("health.healthonboardingview.learn.about.and.choose.ai.reports.1336fa"), systemImage: "text.bubble")
          }
          .accessibilityIdentifier("health.aiInfo")
          if !access.reports.isConfigured {
            Text(access.reports.configurationMessage).font(.footnote).foregroundStyle(.secondary)
          }
        }
        Section {
          NavigationLink(L10n.text("health.healthonboardingview.methods.privacy.and.data.use.8e0893")) { HealthHelpView() }
            .accessibilityIdentifier("health.help")
          Button(access.healthConnected || access.aiEnabled ? L10n.text("health.healthonboardingview.continue.with.trainote.d4888a") : L10n.text("health.healthonboardingview.use.locally.for.now.cc562e")) {
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
      .navigationTitle(L10n.text("health.healthonboardingview.welcome.to.trainote.4df5d8"))
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
      L10n.text("health.healthonboardingview.action.incomplete.223fb3"),
      isPresented: Binding(
        get: { access.errorMessage != nil }, set: { if !$0 { access.clearError() } }
      )
    ) {
      Button(L10n.text("health.healthonboardingview.ok.cb63c6"), role: .cancel) { access.clearError() }
    } message: {
      Text(access.errorMessage ?? L10n.text("health.healthonboardingview.please.try.again.a7e79b"))
    }
  }
}
