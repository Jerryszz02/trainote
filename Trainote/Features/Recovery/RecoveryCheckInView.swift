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
        Section("今天整体感觉") {
          Picker("整体感觉", selection: $draft.feeling) {
            Text("未回答").tag(OverallFeeling?.none)
            Text("好").tag(Optional(OverallFeeling.good))
            Text("一般").tag(Optional(OverallFeeling.normal))
            Text("疲惫").tag(Optional(OverallFeeling.tired))
          }.accessibilityIdentifier("recovery.checkIn.feeling")
          Picker("睡眠感受（可选）", selection: $draft.sleepFeeling) {
            Text("未回答").tag(SleepFeeling?.none)
            Text("好").tag(Optional(SleepFeeling.good))
            Text("一般").tag(Optional(SleepFeeling.normal))
            Text("较差").tag(Optional(SleepFeeling.poor))
          }
        }
        Section {
          ForEach(visibleMuscles) { muscle in
            DisclosureGroup(muscle.displayName) {
              MuscleFeedbackEditor(feedback: binding(for: muscle))
            }
          }
          if !showAllMuscles {
            Button("其他肌群") { showAllMuscles = true }
          }
        } header: {
          Text("最近训练肌群")
        } footer: {
          Text("只填有感受的肌群即可。疼痛和活动受限会独立限制相关训练建议。")
        }
        if let error { Text(error).foregroundStyle(.red) }
      }
      .navigationTitle("十秒体感")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("跳过") { dismiss() }.accessibilityIdentifier("recovery.checkIn.skip")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") { save() }.accessibilityIdentifier("recovery.checkIn.save")
        }
      }
    }
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
    draft.updatedAt = .now
    draft.muscleFeedback = draft.muscleFeedback.filter {
      $0.soreness != nil || $0.hasPain != nil || $0.hasMovementLimitation != nil
    }
    guard draft.feeling != nil || draft.sleepFeeling != nil || !draft.muscleFeedback.isEmpty else {
      dismiss()
      return
    }
    do {
      try repository.saveCheckIn(draft)
      dismiss()
    } catch { self.error = "体感尚未保存，请重试。" }
  }
}

private struct MuscleFeedbackEditor: View {
  @Binding var feedback: MuscleFeedbackValue
  var body: some View {
    Picker("酸痛", selection: $feedback.soreness) {
      Text("未回答").tag(SorenessLevel?.none)
      Text("无").tag(Optional(SorenessLevel.none))
      Text("轻").tag(Optional(SorenessLevel.mild))
      Text("明显").tag(Optional(SorenessLevel.significant))
    }
    .accessibilityIdentifier("recovery.soreness.\(feedback.muscleID.rawValue)")
    Picker("疼痛", selection: $feedback.hasPain) {
      Text("未回答").tag(Bool?.none)
      Text("无").tag(Optional(false))
      Text("有").tag(Optional(true))
    }
    .accessibilityIdentifier("recovery.pain.\(feedback.muscleID.rawValue)")
    Picker("活动受限", selection: $feedback.hasMovementLimitation) {
      Text("未回答").tag(Bool?.none)
      Text("无").tag(Optional(false))
      Text("有").tag(Optional(true))
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
