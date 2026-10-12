import SwiftUI

struct TodayRecoveryCard: View {
  @Environment(\.scenePhase) private var scenePhase
  let integration: HealthRecoveryIntegration
  var advice: TrainingAdviceController? = nil
  let hasRoutines: Bool
  let onOpenTemplates: () -> Void
  let onOpenRecovery: () -> Void
  let onOpenCheckIn: (CheckInValue, @escaping () -> Void) -> Void
  @State private var showPrompt = false
  @State private var error: L10n.Message?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button(
        action: hasRoutines || integration.needsRecoveryReview || integration.failureMessage != nil
          ? onOpenRecovery : onOpenTemplates
      ) {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "lightbulb").font(.title2)
          VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("core.today.s.guidance")).font(.headline)
            Text(recommendationText)
              .font(.subheadline).foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
          Image(systemName: "chevron.right").font(.caption)
        }
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("today.recommendation")
      if integration.healthReadFailed {
        Text(L10n.text("core.health.data.is.temporarily.unavailable.local.records.are.shown"))
          .font(.caption).foregroundStyle(.secondary)
      }
      Divider()
      if showPrompt {
        Text(L10n.text("core.how.do.you.feel.today.add.a.ten.second.check.in.or.skip.it"))
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
    .alert(L10n.text("core.check.in.unavailable"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }))
    {
      Button(L10n.text("core.ok"), role: .cancel) { error = nil }
    } message: {
      Text(error?.text ?? L10n.text("core.please.try.again.later"))
    }
  }

  private var checkInButton: some View {
    Button(L10n.text("core.add.or.edit.a.ten.second.check.in"), systemImage: "heart.text.clipboard") {
      do {
        let draft = try integration.checkInDraft()
        onOpenCheckIn(draft) {
          integration.reloadToday()
          advice?.refresh()
          showPrompt = false
        }
      } catch { self.error = L10n.Message(resolving: { L10n.text("core.could.not.read.your.existing.check.in.please.try.again.later") }) }
    }
    .font(.subheadline)
    .accessibilityIdentifier("today.checkIn.open")
  }

  @ViewBuilder
  private var skipButton: some View {
    if showPrompt {
      Button(L10n.text("core.skip")) { showPrompt = false }
        .font(.subheadline)
        .accessibilityIdentifier("today.checkIn.skipPrompt")
    }
  }

  private func reload() {
    integration.reloadToday()
    advice?.loadRoutines()
    advice?.refresh()
    showPrompt = (try? integration.offerCheckIn()) ?? false
  }

  private var recommendationText: String {
    guard !integration.needsRecoveryReview, advice?.selectedRoutineID != nil,
      let action = advice?.evaluation?.candidates.first?.action
    else { return integration.todayMessage(hasRoutines: hasRoutines) }
    switch action {
    case .keepPlan: return L10n.text("core.use.your.selected.routine.and.check.how.you.feel.before.starting")
    case .reduceSets, .increaseRIR: return L10n.text("core.consider.reducing.today.s.workload.review.working.sets.and.reps.in.reserve")
    case .swapTrainingDay: return L10n.text("core.consider.the.selected.alternative.routine.after.reviewing.its.conditions")
    case .rest, .lightActivity: return L10n.text("core.prioritize.rest.or.light.activity.based.on.how.you.feel.today")
    case .reviewNutrition: return L10n.text("core.your.food.records.differ.from.your.goals.review.them.in.trends")
    case .choosePlan: return L10n.text("core.there.is.not.enough.recorded.data.yet.review.your.routine.recovery.records.and.check.")
    }
  }
}
