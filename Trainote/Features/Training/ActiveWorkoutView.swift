import SwiftData
import SwiftUI
import UIKit

struct ActiveWorkoutView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Query(sort: \Workout.startedAt, order: .reverse) private var history: [Workout]
  @Bindable var workout: Workout
  var isHistoricalEdit = false
  var saveHistory: (() throws -> Void)?
  @State private var showingPicker = false
  @State private var showingDiscard = false
  @State private var message: L10n.Message?
  @AppStorage("training.restSeconds") private var restDuration = 90

  var body: some View {
    List {
      Section(L10n.text("core.workout.details")) {
        TextField(L10n.text("core.workout.name"), text: $workout.title).accessibilityIdentifier("workout.title")
        TextField(L10n.text("core.notes.optional"), text: $workout.notes, axis: .vertical)
        if isHistoricalEdit {
          DatePicker(L10n.text("core.start.time"), selection: $workout.startedAt, in: ...Date.now)
          DatePicker(
            L10n.text("core.end.time"),
            selection: Binding(
              get: { workout.endedAt ?? workout.startedAt }, set: { workout.endedAt = $0 }),
            in: workout.startedAt...max(workout.startedAt, Date.now))
        } else {
          LabeledContent(L10n.text("core.elapsed.time")) {
            Text(workout.startedAt, style: .timer).monospacedDigit()
          }
        }
      }
      if !isHistoricalEdit {
        Section(L10n.text("core.rest.between.sets")) {
          Picker(L10n.text("core.rest.after.completing.a.set"), selection: $restDuration) {
            Text(L10n.text("core.60.sec")).tag(60)
            Text(L10n.text("core.90.sec")).tag(90)
            Text(L10n.text("core.120.sec")).tag(120)
          }.modifier(CoreAdaptivePickerStyle())
          if let end = workout.restEndsAt {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
              let remaining = max(Int(end.timeIntervalSince(timeline.date).rounded(.up)), 0)
              HStack {
                Label(remaining > 0 ? L10n.text("core.resting") : L10n.text("core.rest.finished"), systemImage: "timer")
                Spacer()
                Text(L10n.text("core.sec", remaining)).monospacedDigit().accessibilityIdentifier(
                  "workout.restRemaining")
              }
            }
            HStack {
              Button(L10n.text("core.30.sec")) { workout.restEndsAt = max(end, .now).addingTimeInterval(30) }
              Spacer()
              Button(L10n.text("core.end.rest")) { workout.restEndsAt = nil }
            }
          }
        }
      }
      ForEach(workout.sortedExercises) { exercise in
        WorkoutExerciseEditor(
          exercise: exercise, workout: workout, history: history,
          isDraft: isHistoricalEdit, restDuration: restDuration, reportError: { message = $0 }
        ) {
          workout.exercises.removeAll { $0.id == exercise.id }
          if !isHistoricalEdit { modelContext.delete(exercise) }
          for (index, value) in workout.sortedExercises.enumerated() { value.orderIndex = index }
        }
      }
      Section {
        Button(L10n.text("core.add.exercise"), systemImage: "plus.circle.fill") { showingPicker = true }
          .accessibilityIdentifier("workout.addExercise")
      }
      if !isHistoricalEdit {
        Section {
          Button(L10n.text("core.discard.this.workout"), role: .destructive) { showingDiscard = true }
            .accessibilityIdentifier("workout.discard")
        }
      }
    }
    .localizationTestControls()
    .navigationTitle(isHistoricalEdit ? L10n.text("core.edit.workout") : L10n.text("core.in.progress"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button(isHistoricalEdit ? L10n.text("core.save") : L10n.text("core.done"), action: finish).accessibilityIdentifier(
          "workout.finish")
      }
      if isHistoricalEdit {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("core.cancel")) { dismiss() }.accessibilityIdentifier("workout.edit.cancel")
        }
      }
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button(L10n.text("core.dismiss.keyboard")) {
          UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
      }
    }
    .sheet(isPresented: $showingPicker) {
      ExercisePickerView(title: L10n.text("core.add.workout.exercise")) { item in
        let exercise = RoutineFactory.workoutExercise(
          from: item, orderIndex: workout.exercises.count)
        exercise.workout = workout
        workout.exercises.append(exercise)
      }
    }
    .confirmationDialog(L10n.text("core.discard.this.workout.143"), isPresented: $showingDiscard, titleVisibility: .visible) {
      Button(L10n.text("core.discard.and.delete"), role: .destructive, action: discard)
      Button(L10n.text("core.continue.workout"), role: .cancel) {}
    }
    .alert(
      L10n.text("core.check.your.records"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    ) {
      if !isHistoricalEdit { Button(L10n.text("core.retry.saving")) { persist() } }
      Button(L10n.text("core.ok"), role: .cancel) { message = nil }
    } message: {
      Text(message?.text ?? L10n.text("core.please.try.again"))
    }
    .onChange(of: editFingerprint) { _, _ in persist() }
    .onChange(of: scenePhase) { _, phase in if phase != .active { persist() } }
    .onDisappear { persist() }
  }

  private var editFingerprint: [String] {
    var value: [String] = []
    value.append(String(describing: workout.title))
    value.append(String(describing: workout.notes))
    value.append(String(describing: workout.restEndsAt))
    for exercise in workout.sortedExercises {
      value.append(String(describing: exercise.id))
      value.append(String(describing: exercise.trackingModeRaw))
      value.append(String(describing: exercise.notes))
      for set in exercise.sortedStrengthSets {
        value.append(String(describing: set.id))
        value.append(String(describing: set.weightKilograms))
        value.append(String(describing: set.repetitions))
        value.append(String(describing: set.durationSeconds))
        value.append(String(describing: set.isCompleted))
        value.append(String(describing: set.rir))
        value.append(set.setRoleRaw)
      }
      for cardio in exercise.cardioEntries {
        value.append(String(describing: cardio.id))
        value.append(String(describing: cardio.durationSeconds))
        value.append(String(describing: cardio.distanceKilometers))
        value.append(String(describing: cardio.calories))
      }
    }
    return value
  }

  private func persist() {
    guard !isHistoricalEdit, workout.modelContext != nil, workout.status == .inProgress else {
      return
    }
    do { try modelContext.save() } catch {
      message = L10n.Message(resolving: { L10n.text("core.records.have.not.been.saved.your.input.is.preserved.please.try.again" , String(describing: error.localizedDescription)) })
    }
  }

  private func finish() {
    if let invalid = workout.validationMessage {
      message = L10n.Message(resolving: { workout.validationMessage ?? invalid })
      return
    }
    if isHistoricalEdit {
      guard let end = workout.endedAt, end >= workout.startedAt else {
        message = L10n.Message(resolving: { L10n.text("core.end.time.cannot.be.earlier.than.start.time") })
        return
      }
      do {
        try saveHistory?()
        dismiss()
      } catch { message = L10n.Message(resolving: { L10n.text("core.could.not.save.changes.please.try.again" , String(describing: error.localizedDescription)) }) }
      return
    }
    let previousEnd = workout.endedAt
    let previousRest = workout.restEndsAt
    workout.status = .completed
    workout.endedAt = .now
    workout.restEndsAt = nil
    do {
      try modelContext.save()
      dismiss()
    } catch {
      workout.status = .inProgress
      workout.endedAt = previousEnd
      workout.restEndsAt = previousRest
      message = L10n.Message(resolving: { L10n.text("core.could.not.finish.and.save.the.workout.please.try.again" , String(describing: error.localizedDescription)) })
    }
  }

  private func discard() {
    modelContext.delete(workout)
    do {
      try modelContext.save()
      dismiss()
    } catch {
      modelContext.rollback()
      message = L10n.Message(resolving: { L10n.text("core.delete.failed.your.records.are.preserved" , String(describing: error.localizedDescription)) })
    }
  }
}

private struct WorkoutExerciseEditor: View {
  @Environment(\.modelContext) private var modelContext
  @Bindable var exercise: WorkoutExercise
  let workout: Workout
  let history: [Workout]
  let isDraft: Bool
  let restDuration: Int
  let reportError: (L10n.Message) -> Void
  let onDelete: () -> Void
  @State private var pendingMode: TrackingMode?
  @State private var confirmingMode = false
  @State private var confirmingPrevious = false
  @State private var confirmingDelete = false
  @State private var previousCardioDraft: CardioEntry?

  private var previous: WorkoutExercise? {
    WorkoutInsights.previousExercise(for: exercise, before: workout, history: history)
  }

  var body: some View {
    Section {
      Picker(
        L10n.text("core.tracking.mode"),
        selection: Binding(
          get: { exercise.trackingMode },
          set: { mode in
            guard mode != exercise.trackingMode else { return }
            pendingMode = mode
            confirmingMode = true
          })
      ) {
        ForEach(TrackingMode.allCases) { Text($0.title).tag($0) }
      }.accessibilityIdentifier("exercise.mode.\(exercise.id.uuidString)")
      if let previous {
        VStack(alignment: .leading, spacing: 6) {
          Text(L10n.text("core.previous.performance")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          if previous.trackingMode.usesSets {
            ForEach(
              previous.sortedStrengthSets.filter {
                $0.isCompleted && $0.isValid(for: previous.trackingMode)
              }
            ) { set in
              Text(
                L10n.text("core.set.154", set.orderIndex + 1, String(describing: WorkoutValueFormatting.set(set, mode: previous.trackingMode)))
              )
              .font(.caption).monospacedDigit()
            }
          } else if let cardio = previous.cardioEntries.first(where: { $0.isValid }) {
            Text(L10n.text("core.min.km", cardio.durationSeconds / 60, String(describing: cardio.distanceKilometers.formatted(.number.locale(L10n.locale)))))
              .font(.caption)
          }
          Button(L10n.text("core.use.previous.completed.values")) {
            if exercise.trackingMode.usesSets {
              confirmingPrevious = true
            } else {
              copyPrevious()
            }
          }
          .accessibilityIdentifier("exercise.history.apply.\(exercise.id.uuidString)")
          .sheet(item: $previousCardioDraft) { draft in
            NavigationStack {
              Form {
                Section {
                  LabeledContent(
                    L10n.text("core.duration"), value: L10n.text("core.min.sec" , String(describing: draft.durationSeconds / 60), String(describing: draft.durationSeconds % 60)))
                  LabeledContent(L10n.text("core.distance"), value: "\(draft.distanceKilometers.formatted(.number.locale(L10n.locale))) km")
                  LabeledContent(L10n.text("core.calories.burned"), value: "\(draft.calories.formatted(.number.locale(L10n.locale))) kcal")
                } footer: {
                  Text(L10n.text("core.these.are.your.previous.results.confirm.only.if.you.completed.the.same.workout.this.t"))
                }
                Button(L10n.text("core.confirm.completed.this.time")) {
                  guard let cardio = exercise.cardioEntries.first else { return }
                  cardio.durationSeconds = draft.durationSeconds
                  cardio.distanceKilometers = draft.distanceKilometers
                  cardio.calories = draft.calories
                  previousCardioDraft = nil
                }
                .accessibilityIdentifier("cardio.history.confirm")
              }
              .localizationTestControls()
    .navigationTitle(L10n.text("core.confirm.today.s.cardio.results"))
              .navigationBarTitleDisplayMode(.inline)
              .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                  Button(L10n.text("core.cancel")) { previousCardioDraft = nil }
                    .accessibilityIdentifier("cardio.history.cancel")
                }
              }
            }
          }
        }
      }
      if exercise.trackingMode.usesSets {
        ForEach(exercise.sortedStrengthSets) { set in
          StrengthSetRow(strengthSet: set, mode: exercise.trackingMode) {
            if !set.isCompleted && !set.isValid(for: exercise.trackingMode) {
              reportError(L10n.Message(resolving: { L10n.text("core.enter.valid.first", exercise.trackingMode == .duration ? L10n.text("core.duration") : L10n.text("core.repetitions.and.weight")) }))
              return
            }
            set.isCompleted.toggle()
            if set.isCompleted && !isDraft {
              workout.restEndsAt = Date.now.addingTimeInterval(Double(restDuration))
            }
          } onDelete: {
            exercise.strengthSets.removeAll { $0.id == set.id }
            if !isDraft { modelContext.delete(set) }
            for (index, value) in exercise.sortedStrengthSets.enumerated() {
              value.orderIndex = index
            }
          }
        }
        Button(L10n.text("core.add.a.set"), systemImage: "plus") { addSet() }
      } else if let cardio = exercise.cardioEntries.first {
        CardioEntryEditor(cardio: cardio)
      }
      TextField(L10n.text("core.exercise.notes.optional"), text: $exercise.notes, axis: .vertical)
      Button(L10n.text("core.remove.exercise"), role: .destructive) { confirmingDelete = true }
    } header: {
      VStack(alignment: .leading, spacing: 3) {
        Text(exercise.displayName)
      }
    }
    .confirmationDialog(L10n.text("core.change.tracking.mode"), isPresented: $confirmingMode, titleVisibility: .visible) {
      Button(L10n.text("core.change")) { applyMode() }
      Button(L10n.text("core.cancel"), role: .cancel) { pendingMode = nil }
    } message: {
      Text(L10n.text("core.values.for.each.mode.will.be.preserved.set.completion.and.rir.will.be.reset.verify.yo"))
    }
    .confirmationDialog(L10n.text("core.replace.current.values.with.previous.results"), isPresented: $confirmingPrevious, titleVisibility: .visible)
    {
      Button(L10n.text("core.apply.and.reset.completion")) { copyPrevious() }
      Button(L10n.text("core.cancel"), role: .cancel) {}
    } message: {
      Text(L10n.text("core.mark.copied.sets.as.completed.again.and.enter.rir.based.on.how.you.feel.this.time"))
    }
    .confirmationDialog(L10n.text("core.remove.this.exercise.and.its.recorded.sets"), isPresented: $confirmingDelete, titleVisibility: .visible)
    {
      Button(L10n.text("core.remove.exercise"), role: .destructive, action: onDelete)
      Button(L10n.text("core.cancel"), role: .cancel) {}
    }
  }

  private func addSet() {
    let last = exercise.sortedStrengthSets.last
    let set = StrengthSet(
      orderIndex: exercise.strengthSets.count, weightKilograms: last?.weightKilograms ?? 0,
      repetitions: last?.repetitions ?? 8, durationSeconds: last?.durationSeconds ?? 30,
      setRole: .working)
    set.exercise = exercise
    exercise.strengthSets.append(set)
  }

  private func applyMode() {
    guard let mode = pendingMode else { return }
    exercise.trackingMode = mode
    for set in exercise.strengthSets {
      set.isCompleted = false
      set.rir = nil
    }
    if mode.usesSets && exercise.strengthSets.isEmpty { addSet() }
    if mode == .cardio && exercise.cardioEntries.isEmpty {
      let cardio = CardioEntry()
      cardio.exercise = exercise
      exercise.cardioEntries.append(cardio)
    }
    pendingMode = nil
  }

  private func copyPrevious() {
    guard let previous else { return }
    if exercise.trackingMode.usesSets {
      let oldSets = exercise.strengthSets
      exercise.strengthSets = previous.sortedStrengthSets.filter {
        $0.isCompleted && $0.isValid(for: previous.trackingMode)
      }.enumerated().map { index, old in
        let set = StrengthSet(
          orderIndex: index, weightKilograms: old.weightKilograms, repetitions: old.repetitions,
          durationSeconds: old.durationSeconds,
          setRole: old.setRole == .unknown ? .working : old.setRole)
        set.exercise = exercise
        return set
      }
      if !isDraft { oldSets.forEach { modelContext.delete($0) } }
    } else if let old = previous.cardioEntries.first(where: { $0.isValid }) {
      // Keep copied values detached from the current result until explicitly confirmed.
      previousCardioDraft = CardioEntry(
        durationSeconds: old.durationSeconds, distanceKilometers: old.distanceKilometers,
        calories: old.calories)
    }
  }
}

private struct StrengthSetRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Bindable var strengthSet: StrengthSet
  let mode: TrackingMode
  let onComplete: () -> Void
  let onDelete: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      let headerLayout = dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        : AnyLayout(HStackLayout())
      headerLayout {
        Button(action: onComplete) {
          Label(
            L10n.text("core.set", strengthSet.orderIndex + 1),
            systemImage: strengthSet.isCompleted ? "checkmark.circle.fill" : "circle"
          )
          .foregroundStyle(strengthSet.isCompleted ? Color.green : Color.primary)
          .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(
          L10n.text("core.set.171", strengthSet.orderIndex + 1, String(describing: strengthSet.isCompleted ? L10n.text("core.completed") : L10n.text("core.mark.complete")))
        )
        .accessibilityIdentifier("strengthSet.complete.\(strengthSet.id.uuidString)")
        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
        Button(L10n.text("core.delete.set"), systemImage: "trash", role: .destructive, action: onDelete)
          .labelStyle(.iconOnly).buttonStyle(.borderless)
      }
      Picker(L10n.text("core.set.type"), selection: Binding(
        get: { strengthSet.setRole }, set: { strengthSet.setRole = $0 }
      )) {
        Text(L10n.text("core.working.set")).tag(SetRole.working)
        Text(L10n.text("core.warm.up.set")).tag(SetRole.warmup)
        if strengthSet.setRole == .unknown { Text(L10n.text("core.unspecified.in.history")).tag(SetRole.unknown) }
      }
      .accessibilityIdentifier("strengthSet.role.\(strengthSet.id.uuidString)")
      if mode == .strength || mode == .repetitions {
        Picker(L10n.text("core.reps.in.reserve.rir"), selection: $strengthSet.rir) {
          Text(L10n.text("core.rir.unset")).tag(Int?.none)
          ForEach(0...5, id: \.self) { value in
            Text(value == 5 ? "5+" : value.formatted(.number.locale(L10n.locale)))
              .accessibilityLabel(value == 5 ? L10n.text("core.5.or.more.reps") : L10n.text("core.reps", value))
              .tag(Optional(value))
          }
        }
        .accessibilityIdentifier("strengthSet.rir.\(strengthSet.id.uuidString)")
        Text(L10n.text("core.estimate.how.many.more.reps.you.could.have.completed.at.the.end.of.this.set.optional"))
          .font(.caption).foregroundStyle(.secondary)
      }
      if mode == .strength {
        HStack {
          Button {
            strengthSet.weightKilograms = max(strengthSet.weightKilograms - 2.5, 0)
          } label: {
            Image(systemName: "minus.circle")
          }
          .accessibilityLabel(L10n.text("core.decrease.weight.by.2.5.kg")).buttonStyle(.borderless)
          StableNumberField(
            L10n.text("core.weight"), value: $strengthSet.weightKilograms,
            format: .number.precision(.fractionLength(0...2)).locale(L10n.locale)
          )
          .keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel(L10n.text("core.weight"))
          .accessibilityIdentifier("strengthSet.weight.\(strengthSet.id.uuidString)")
          Text("kg").foregroundStyle(.secondary)
          Button {
            strengthSet.weightKilograms = min(strengthSet.weightKilograms + 2.5, 10_000)
          } label: {
            Image(systemName: "plus.circle")
          }
          .accessibilityLabel(L10n.text("core.increase.weight.by.2.5.kg")).buttonStyle(.borderless)
        }
      }
      HStack {
        Text(mode == .duration ? L10n.text("core.duration") : L10n.text("core.repetitions"))
        Spacer()
        StableNumberField(
          mode == .duration ? L10n.text("core.seconds") : L10n.text("core.repetitions"),
          value: mode == .duration ? $strengthSet.durationSeconds : $strengthSet.repetitions,
          format: .number.locale(L10n.locale)
        )
        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
        .accessibilityLabel(mode == .duration ? L10n.text("core.duration.in.seconds") : L10n.text("core.repetitions"))
        .accessibilityIdentifier(
          "strengthSet.\(mode == .duration ? "duration" : "repetitions").\(strengthSet.id.uuidString)"
        )
        Text(mode == .duration ? L10n.text("core.sec.187") : L10n.text("core.reps.188")).foregroundStyle(.secondary)
      }
    }.padding(.vertical, 5)
  }
}

private struct CardioEntryEditor: View {
  @Bindable var cardio: CardioEntry
  var body: some View {
    LabeledContent(L10n.text("core.duration.minutes")) {
      StableNumberField("0", value: durationMinutes, format: .number.precision(.fractionLength(0...1)).locale(L10n.locale))
        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier(
          "cardio.duration")
    }
    LabeledContent(L10n.text("core.distance.km.optional")) {
      StableNumberField(
        "0", value: $cardio.distanceKilometers, format: .number.precision(.fractionLength(0...2)).locale(L10n.locale)
      )
      .keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel(L10n.text("core.distance.in.kilometers"))
      .accessibilityIdentifier("cardio.distance")
    }
    LabeledContent(L10n.text("core.calories.burned.kcal.optional")) {
      StableNumberField("0", value: $cardio.calories, format: .number.precision(.fractionLength(0...1)).locale(L10n.locale))
        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel(L10n.text("core.calories.burned.in.kilocalories"))
        .accessibilityIdentifier("cardio.calories")
    }
  }
  private var durationMinutes: Binding<Double> {
    Binding(
      get: { Double(cardio.durationSeconds) / 60 },
      set: {
        guard $0.isFinite else { return }
        cardio.durationSeconds = Int(min(max($0, 0), 10_080) * 60)
      })
  }
}

enum WorkoutValueFormatting {
  static func set(_ set: StrengthSet, mode: TrackingMode) -> String {
    switch mode {
    case .strength:
      return
        L10n.text("core.kg.reps.194" , String(describing: set.weightKilograms.formatted(.number.precision(.fractionLength(0...2)).locale(L10n.locale))), String(describing: set.repetitions))
    case .repetitions: return L10n.text("core.reps", set.repetitions)
    case .duration: return L10n.text("core.sec", set.durationSeconds)
    case .cardio: return L10n.text("core.cardio")
    }
  }
}
