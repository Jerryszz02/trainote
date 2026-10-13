import SwiftUI

/// A detached draft ensures skip/cancel never saves an implicit negative response.
struct RecoveryCheckInView: View {
  @Environment(\.dismiss) private var dismiss
  let repository: any AnalysisRepository
  let suggestedMuscles: [MuscleID]
  @State var draft: CheckInValue
  @State private var error: String?
  @State private var showAllMuscles = false

  var body: some View {
    NavigationStack {
      Form {
        Section(L10n.text("health.recoverycheckinview.overall.feeling.today.141564")) {
          Picker(L10n.text("health.recoverycheckinview.overall.feeling.0eb92f"), selection: $draft.feeling) {
            Text(L10n.text("health.recoverycheckinview.unanswered.db09b9")).tag(OverallFeeling?.none)
            Text(L10n.text("health.recoverycheckinview.ok.27e4fe")).tag(Optional(OverallFeeling.good))
            Text(L10n.text("health.recoverycheckinview.okay.f0aacc")).tag(Optional(OverallFeeling.normal))
            Text(L10n.text("health.recoverycheckinview.tired.8174d1")).tag(Optional(OverallFeeling.tired))
          }.accessibilityIdentifier("recovery.checkIn.feeling")
          Picker(L10n.text("health.recoverycheckinview.sleep.quality.optional.229e9c"), selection: $draft.sleepFeeling) {
            Text(L10n.text("health.recoverycheckinview.unanswered.db09b9")).tag(SleepFeeling?.none)
            Text(L10n.text("health.recoverycheckinview.ok.27e4fe")).tag(Optional(SleepFeeling.good))
            Text(L10n.text("health.recoverycheckinview.okay.f0aacc")).tag(Optional(SleepFeeling.normal))
            Text(L10n.text("health.recoverycheckinview.poor.8046a5")).tag(Optional(SleepFeeling.poor))
          }
        }
        Section {
          ForEach(visibleMuscles) { muscle in
            DisclosureGroup(muscle.displayName) {
              MuscleFeedbackEditor(feedback: binding(for: muscle))
            }
          }
          if !showAllMuscles {
            Button(L10n.text("health.recoverycheckinview.other.muscles.5ca4ad")) { showAllMuscles = true }
          }
        } header: {
          Text(L10n.text("health.recoverycheckinview.recently.trained.muscles.2369da"))
        } footer: {
          Text(L10n.text("health.recoverycheckinview.only.fill.in.muscles.you.notice.f6f0c4"))
        }
        if let error { Text(L10n.text(error)).foregroundStyle(.red) }
      }
      .navigationTitle(L10n.text("health.recoverycheckinview.quick.check.in.70302a"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("health.recoverycheckinview.skip.31a985")) { dismiss() }.accessibilityIdentifier("recovery.checkIn.skip")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("health.recoverycheckinview.save.fadf24")) { save() }.accessibilityIdentifier("recovery.checkIn.save")
        }
      }
    }
    #if DEBUG
      .onAppear { HealthUITestTrace.record("checkIn.appear") }
      .onDisappear { HealthUITestTrace.record("checkIn.disappear") }
      .onChange(of: draft.feeling) { _, feeling in
        HealthUITestTrace.record("checkIn.feelingChanged", flags: [("answered", feeling != nil)])
      }
    #endif
  }
  private var visibleMuscles: [MuscleID] {
    showAllMuscles
      ? MuscleID.allCases
      : MuscleID.allCases.filter { muscle in
        suggestedMuscles.contains(muscle)
          || draft.muscleFeedback.contains(where: { $0.muscleID == muscle })
      }
  }
  private func binding(for muscle: MuscleID) -> Binding<MuscleFeedbackValue> {
    Binding(
      get: {
        draft.muscleFeedback.first { $0.muscleID == muscle }
          ?? .init(id: UUID(), muscleID: muscle, recordedAt: draft.updatedAt)
      },
      set: { value in
        var updated = value
        updated.recordedAt = .now
        if let index = draft.muscleFeedback.firstIndex(where: { $0.muscleID == muscle }) {
          draft.muscleFeedback[index] = updated
        } else {
          draft.muscleFeedback.append(updated)
        }
      })
  }
  private func save() {
    do {
      try RecoveryCheckInWriter.save(draft, repository: repository, at: .now)
      dismiss()
    } catch { self.error = "health.recoverycheckinview.check.in.has.not.been.saved.f6b8d2" }
  }

}

@MainActor
enum RecoveryCheckInWriter {
  /// First-time empty drafts are skipped; clearing an existing answer must persist the empty value.
  @discardableResult
  static func save(_ draft: CheckInValue, repository: any AnalysisRepository, at date: Date) throws
    -> Bool
  {
    var value = draft
    value.updatedAt = date
    value.muscleFeedback = value.muscleFeedback.filter {
      $0.soreness != nil || $0.hasPain != nil || $0.hasMovementLimitation != nil
    }
    let hasAnswers =
      value.feeling != nil || value.sleepFeeling != nil || !value.muscleFeedback.isEmpty
    let isExisting = try repository.manualRecords().checkIns.contains { $0.id == value.id }
    guard hasAnswers || isExisting else { return false }
    try repository.saveCheckIn(value)
    return true
  }
}

private struct MuscleFeedbackEditor: View {
  @Binding var feedback: MuscleFeedbackValue
  var body: some View {
    Picker(L10n.text("health.recoverycheckinview.soreness.1796dc"), selection: $feedback.soreness) {
      Text(L10n.text("health.recoverycheckinview.unanswered.db09b9")).tag(SorenessLevel?.none)
      Text(L10n.text("health.recoverycheckinview.none.720777")).tag(Optional(SorenessLevel.none))
      Text(L10n.text("health.recoverycheckinview.mild.eb4f04")).tag(Optional(SorenessLevel.mild))
      Text(L10n.text("health.recoverycheckinview.significant.d13e81")).tag(Optional(SorenessLevel.significant))
    }
    .accessibilityIdentifier("recovery.soreness.\(feedback.muscleID.rawValue)")
    Picker(L10n.text("health.recoverycheckinview.pain.2515a7"), selection: $feedback.hasPain) {
      Text(L10n.text("health.recoverycheckinview.unanswered.db09b9")).tag(Bool?.none)
      Text(L10n.text("health.recoverycheckinview.none.720777")).tag(Optional(false))
      Text(L10n.text("health.recoverycheckinview.yes.fbd5b7")).tag(Optional(true))
    }
    .accessibilityIdentifier("recovery.pain.\(feedback.muscleID.rawValue)")
    Picker(L10n.text("health.recoverycheckinview.limited.movement.4b936a"), selection: $feedback.hasMovementLimitation) {
      Text(L10n.text("health.recoverycheckinview.unanswered.db09b9")).tag(Bool?.none)
      Text(L10n.text("health.recoverycheckinview.none.720777")).tag(Optional(false))
      Text(L10n.text("health.recoverycheckinview.yes.fbd5b7")).tag(Optional(true))
    }
    .accessibilityIdentifier("recovery.limitation.\(feedback.muscleID.rawValue)")
  }
}

@MainActor
enum RecoveryCheckInPrompt {
  static func offer(
    repository: any AnalysisRepository, records: ManualHealthRecords,
    date: Date, timeZone: TimeZone
  ) throws -> Bool {
    var preferences = records.preferences
    let today = AnalysisFingerprint.localDate(date, timeZone: timeZone)
    guard preferences.checkInPromptsEnabled, preferences.lastCheckInPromptDate != today else {
      return false
    }
    let alreadyAnswered = records.checkIns.contains {
      $0.localDate == today && $0.timeZoneIdentifier == timeZone.identifier
    }
    let recentlyParticipated = records.checkIns.contains {
      $0.updatedAt <= date && date.timeIntervalSince($0.updatedAt) <= 7 * 86_400
    }
    let shouldOffer =
      !alreadyAnswered && (preferences.lastCheckInPromptDate == nil || recentlyParticipated)
    if shouldOffer {
      preferences.lastCheckInPromptDate = today
      try repository.savePreferences(preferences)
    }
    return shouldOffer
  }
}
