import SwiftData
import SwiftUI

private struct RoutinePresentation: Identifiable {
  let routine: Routine
  let original: Routine?
  let isNew: Bool
  var id: UUID { routine.id }
}

struct RoutinesView: View {
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \Routine.updatedAt, order: .reverse)
  private var routines: [Routine]
  @Query private var workouts: [Workout]

  @State private var presentation: RoutinePresentation?
  @State private var pendingDeletion: Routine?
  @State private var deletionError: L10n.Message?
  @State private var selectedWorkout: Workout?
  @State private var startError: L10n.Message?

  private var activeWorkout: Workout? { workouts.first { $0.status == .inProgress } }

  var body: some View {
    List {
      if let activeWorkout {
        Section(L10n.text("core.a.workout.is.already.in.progress")) {
          Text(L10n.text("core.finish.or.discard.before.starting.another.workout" , String(describing: activeWorkout.title)))
            .font(.subheadline).foregroundStyle(.secondary)
          Button(L10n.text("core.continue.workout"), systemImage: "play.fill") { selectedWorkout = activeWorkout }
            .accessibilityIdentifier("routine.continueWorkout")
        }
      }
      if routines.isEmpty {
        ContentUnavailableView(
          L10n.text("core.no.routines.yet"),
          systemImage: "list.bullet.rectangle",
          description: Text(L10n.text("core.save.your.usual.exercises.and.default.training.values.as.a.routine"))
        )
      } else {
        ForEach(routines) { routine in
          VStack(alignment: .leading, spacing: 12) {
            Button {
              presentation = RoutinePresentation(
                routine: draft(of: routine), original: routine, isNew: false)
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(routine.name).font(.body.weight(.medium))
                  Text(L10n.text("core.exercises", routine.exercises.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                  .font(.caption.bold())
                  .foregroundStyle(.tertiary)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("routine.edit.\(routine.id.uuidString)")
            Button(L10n.text("core.start.workout"), systemImage: "play.fill") { start(routine) }
              .buttonStyle(.borderless)
              .disabled(activeWorkout != nil)
              .accessibilityIdentifier("routine.start.\(routine.id.uuidString)")
          }
          .padding(.vertical, 4)
          .swipeActions {
            Button(L10n.text("core.delete"), role: .destructive) { pendingDeletion = routine }
          }
        }
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(L10n.text("core.new.routine"), systemImage: "plus") { createRoutine() }
          .accessibilityIdentifier("routine.create")
      }
    }
    .sheet(item: $presentation) { value in
      RoutineEditorView(routine: value.routine, original: value.original, isNew: value.isNew)
    }
    .navigationDestination(item: $selectedWorkout) { ActiveWorkoutView(workout: $0) }
    .alert(
      L10n.text("core.cannot.start.workout"),
      isPresented: Binding(get: { startError != nil }, set: { if !$0 { startError = nil } })
    ) {
      Button(L10n.text("core.ok"), role: .cancel) {}
    } message: {
      Text(startError?.text ?? L10n.text("core.please.try.again"))
    }
    .alert(L10n.text("core.delete.this.routine"), isPresented: deletionAlertBinding, presenting: pendingDeletion) {
      routine in
      Button(L10n.text("core.delete"), role: .destructive) {
        modelContext.delete(routine)
        do { try modelContext.save() } catch {
          modelContext.rollback()
          deletionError = L10n.Message(resolving: { error.localizedDescription })
        }
        pendingDeletion = nil
      }
      Button(L10n.text("core.cancel"), role: .cancel) { pendingDeletion = nil }
    } message: { _ in
      Text(L10n.text("core.completed.and.ongoing.workouts.will.remain.unchanged"))
    }
    .alert(
      L10n.text("core.delete.failed"),
      isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })
    ) {
      Button(L10n.text("core.ok"), role: .cancel) {}
    } message: {
      Text(deletionError?.text ?? L10n.text("core.please.try.again"))
    }
  }

  private var deletionAlertBinding: Binding<Bool> {
    Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
  }

  private func start(_ routine: Routine) {
    do {
      // Check the store again at the action boundary, even if the displayed list is stale.
      if let active = try modelContext.fetch(FetchDescriptor<Workout>()).first(where: {
        $0.status == .inProgress
      }) {
        selectedWorkout = active
        return
      }
      guard !routine.exercises.isEmpty, routine.exercises.allSatisfy(\.hasValidDefaults) else {
        startError = L10n.Message(resolving: { L10n.text("core.this.routine.has.invalid.values.edit.it.first") })
        return
      }
      let workout = RoutineFactory.workout(from: routine)
      modelContext.insert(workout)
      try modelContext.save()
      selectedWorkout = workout
    } catch {
      modelContext.rollback()
      startError = L10n.Message(resolving: { error.localizedDescription })
    }
  }

  private func createRoutine() {
    let routine = Routine(name: L10n.text("core.new.routine.256"))
    presentation = RoutinePresentation(routine: routine, original: nil, isNew: true)
  }

  private func draft(of source: Routine) -> Routine {
    let draft = Routine(
      id: source.id, name: source.name, notes: source.notes, createdAt: source.createdAt,
      updatedAt: source.updatedAt)
    draft.exercises = source.sortedExercises.map { value in
      let item = RoutineExercise(
        id: value.id, sourceExerciseID: value.sourceExerciseID,
        nameEnSnapshot: value.nameEnSnapshot, nameZhSnapshot: value.nameZhSnapshot,
        orderIndex: value.orderIndex, trackingMode: value.trackingMode,
        defaultSetCount: value.defaultSetCount, defaultRepetitions: value.defaultRepetitions,
        defaultWeightKilograms: value.defaultWeightKilograms,
        defaultDurationSeconds: value.defaultDurationSeconds,
        defaultDistanceKilometers: value.defaultDistanceKilometers)
      item.routine = draft
      return item
    }
    return draft
  }
}

private enum RoutineEditorSheet: String, Identifiable {
  case exercisePicker
  var id: String { rawValue }
}

private struct RoutineEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @Bindable var routine: Routine
  let original: Routine?
  let isNew: Bool

  @State private var presentedSheet: RoutineEditorSheet?
  @State private var showCancelConfirmation = false
  @State private var saveError: L10n.Message?

  private var canSave: Bool {
    !routine.name.trimmed.isEmpty && !routine.exercises.isEmpty
      && routine.exercises.allSatisfy(\.hasValidDefaults)
  }

  var body: some View {
    NavigationStack {
      List {
        Section(L10n.text("core.basic.details")) {
          TextField(L10n.text("core.routine.name"), text: $routine.name)
            .accessibilityIdentifier("routine.name")
          TextField(L10n.text("core.notes.optional"), text: $routine.notes, axis: .vertical)
        }

        Section(L10n.text("core.exercises.259")) {
          if routine.exercises.isEmpty {
            Text(L10n.text("core.no.exercises.yet"))
              .foregroundStyle(.secondary)
          }
          ForEach(routine.sortedExercises) { exercise in
            RoutineExerciseEditor(exercise: exercise) {
              delete(exercise)
            }
          }
          .onMove(perform: move)

          Button(L10n.text("core.add.exercise"), systemImage: "plus.circle.fill") {
            presentedSheet = .exercisePicker
          }
          .accessibilityIdentifier("routine.addExercise")
        }
      }
      .environment(\.editMode, .constant(.active))
      .localizationTestControls()
      .navigationTitle(isNew ? L10n.text("core.new.routine") : L10n.text("core.edit.routine"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(isNew ? L10n.text("core.cancel") : L10n.text("core.close")) {
            if isNew { showCancelConfirmation = true } else { dismiss() }
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("core.save"), action: save)
            .disabled(!canSave)
            .accessibilityIdentifier("routine.save")
        }
      }
      .toolbar { NutritionKeyboardDoneToolbar() }
      .sheet(item: $presentedSheet) { sheet in
        switch sheet {
        case .exercisePicker:
          ExercisePickerView(title: L10n.text("core.add.routine.exercise")) { item in
            add(item)
          }
        }
      }
      .alert(
        L10n.text("core.cannot.save.routine"),
        isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
      ) {
        Button(L10n.text("core.ok"), role: .cancel) {}
      } message: {
        Text(saveError?.text ?? L10n.text("core.please.try.again.later"))
      }
      .confirmationDialog(
        L10n.text("core.discard.this.new.routine"), isPresented: $showCancelConfirmation, titleVisibility: .visible
      ) {
        Button(L10n.text("core.discard"), role: .destructive) {
          dismiss()
        }
        Button(L10n.text("core.keep.editing"), role: .cancel) {}
      }
    }
  }

  private func add(_ item: ExerciseCatalogItem) {
    let exercise = RoutineFactory.routineExercise(
      from: item,
      orderIndex: routine.exercises.count
    )
    exercise.routine = routine
    routine.exercises.append(exercise)
    routine.updatedAt = .now
  }

  private func delete(_ exercise: RoutineExercise) {
    routine.exercises.removeAll { $0.id == exercise.id }
    for (index, item) in routine.sortedExercises.enumerated() {
      item.orderIndex = index
    }
    routine.updatedAt = .now
  }

  private func move(from offsets: IndexSet, to destination: Int) {
    var ordered = routine.sortedExercises
    ordered.move(fromOffsets: offsets, toOffset: destination)
    for (index, item) in ordered.enumerated() { item.orderIndex = index }
    routine.updatedAt = .now
  }

  private func save() {
    guard canSave else { return }
    routine.name = routine.name.trimmed
    routine.updatedAt = .now
    if let original {
      original.name = routine.name
      original.notes = routine.notes
      original.updatedAt = routine.updatedAt
      original.exercises.forEach { modelContext.delete($0) }
      original.exercises = routine.sortedExercises.map { value in
        let item = RoutineExercise(
          sourceExerciseID: value.sourceExerciseID, nameEnSnapshot: value.nameEnSnapshot,
          nameZhSnapshot: value.nameZhSnapshot, orderIndex: value.orderIndex,
          trackingMode: value.trackingMode, defaultSetCount: value.defaultSetCount,
          defaultRepetitions: value.defaultRepetitions,
          defaultWeightKilograms: value.defaultWeightKilograms,
          defaultDurationSeconds: value.defaultDurationSeconds,
          defaultDistanceKilometers: value.defaultDistanceKilometers)
        item.routine = original
        return item
      }
    } else {
      let saved = Routine(name: routine.name, notes: routine.notes)
      saved.exercises = routine.sortedExercises.map { value in
        let item = RoutineExercise(
          sourceExerciseID: value.sourceExerciseID, nameEnSnapshot: value.nameEnSnapshot,
          nameZhSnapshot: value.nameZhSnapshot, orderIndex: value.orderIndex,
          trackingMode: value.trackingMode, defaultSetCount: value.defaultSetCount,
          defaultRepetitions: value.defaultRepetitions,
          defaultWeightKilograms: value.defaultWeightKilograms,
          defaultDurationSeconds: value.defaultDurationSeconds,
          defaultDistanceKilometers: value.defaultDistanceKilometers)
        item.routine = saved
        return item
      }
      modelContext.insert(saved)
    }
    do {
      try modelContext.save()
      dismiss()
    } catch {
      modelContext.rollback()
      saveError = L10n.Message(resolving: { error.localizedDescription })
    }
  }
}

private struct RoutineExerciseEditor: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .body) private var numberWidth = 48.0
  @ScaledMetric(relativeTo: .body) private var weightWidth = 70.0
  @Bindable var exercise: RoutineExercise
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading) {
          Text(exercise.displayName).font(.body.weight(.medium))
        }
        Spacer()
        Button(L10n.text("core.delete"), systemImage: "trash", role: .destructive, action: onDelete)
          .labelStyle(.iconOnly)
      }

      Picker(L10n.text("core.tracking.mode"), selection: $exercise.trackingMode) {
        ForEach(TrackingMode.allCases) { Text($0.title).tag($0) }
      }
      .accessibilityIdentifier("routine.mode.\(exercise.id.uuidString)")

      if exercise.trackingMode == .strength {
        let layout = dynamicTypeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
          : AnyLayout(HStackLayout())
        layout {
          numberField(L10n.text("core.sets.265"), value: $exercise.defaultSetCount)
          numberField(L10n.text("core.reps.188"), value: $exercise.defaultRepetitions)
          LabeledContent("kg") {
            StableNumberField(
              "0", value: $exercise.defaultWeightKilograms,
              format: .number.precision(.fractionLength(0...2)).locale(L10n.locale)
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: weightWidth)
          }
        }
      } else if exercise.trackingMode == .repetitions {
        numberField(L10n.text("core.sets.266"), value: $exercise.defaultSetCount)
        numberField(L10n.text("core.repetitions"), value: $exercise.defaultRepetitions)
      } else if exercise.trackingMode == .duration {
        numberField(L10n.text("core.sets.266"), value: $exercise.defaultSetCount)
        numberField(L10n.text("core.seconds.per.set"), value: $exercise.defaultDurationSeconds)
      } else {
        LabeledContent(L10n.text("core.default.duration")) {
          HStack {
            StableNumberField(
              "0", value: durationMinutes, format: .number.precision(.fractionLength(0...1)).locale(L10n.locale)
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            Text(L10n.text("core.minutes")).foregroundStyle(.secondary)
          }
        }
        LabeledContent(L10n.text("core.default.distance")) {
          HStack {
            StableNumberField(
              "0", value: $exercise.defaultDistanceKilometers,
              format: .number.precision(.fractionLength(0...2)).locale(L10n.locale)
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            Text("km").foregroundStyle(.secondary)
          }
        }
      }
    }
    .padding(.vertical, 4)
  }

  private var durationMinutes: Binding<Double> {
    Binding(
      get: { Double(exercise.defaultDurationSeconds) / 60 },
      set: {
        if $0.isFinite { exercise.defaultDurationSeconds = Int(min(max($0, 0), 10_080) * 60) }
      }
    )
  }

  private func numberField(_ title: String, value: Binding<Int>) -> some View {
    LabeledContent(title) {
      StableNumberField("0", value: value, format: .number.locale(L10n.locale))
        .keyboardType(.numberPad)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: numberWidth)
    }
  }
}
