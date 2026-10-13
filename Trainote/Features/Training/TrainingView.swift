import SwiftData
import SwiftUI

private enum TrainingSheet: String, Identifiable {
  case start

  var id: String { rawValue }
}

struct TrainingView: View {
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \Workout.startedAt, order: .reverse)
  private var workouts: [Workout]

  @State private var presentedSheet: TrainingSheet?
  @State private var pendingDeletion: Workout?
  @State private var selectedWorkout: Workout?
  @State private var queuedWorkout: Workout?
  @State private var saveError: L10n.Message?

  @Binding var startRequested: Bool

  private var activeWorkout: Workout? {
    workouts.first { $0.status == .inProgress }
  }

  private var completedWorkouts: [Workout] {
    workouts.filter { $0.status == .completed }
  }

  var body: some View {
    List {
      Section(L10n.text("core.library")) {
        NavigationLink(L10n.text("core.exercise.catalog"), destination: LibraryView(initialSection: .exercises))
          .accessibilityIdentifier("training.exercises")
        NavigationLink(L10n.text("core.routines"), destination: LibraryView(initialSection: .routines))
          .accessibilityIdentifier("training.routines")
      }
      if let activeWorkout {
        Section(L10n.text("core.in.progress")) {
          NavigationLink {
            ActiveWorkoutView(workout: activeWorkout)
          } label: {
            WorkoutRow(workout: activeWorkout)
          }
          .accessibilityIdentifier("training.activeWorkout")
        }
      }

      Section(L10n.text("core.history")) {
        if completedWorkouts.isEmpty {
          ContentUnavailableView(
            L10n.text("core.no.completed.workouts.yet"),
            systemImage: "figure.strengthtraining.traditional",
            description: Text(L10n.text("recording.first.workout"))
          )
          .frame(maxWidth: .infinity)
          if activeWorkout == nil {
            Button(L10n.text("core.start.workout")) { presentedSheet = .start }
              .accessibilityIdentifier("training.emptyStart")
          }
        } else {
          ForEach(completedWorkouts) { workout in
            NavigationLink {
              WorkoutDetailView(workout: workout)
            } label: {
              WorkoutRow(workout: workout)
            }
            .swipeActions {
              Button(L10n.text("core.delete"), role: .destructive) {
                pendingDeletion = workout
              }
            }
          }
        }
      }
    }
    .navigationTitle(L10n.text("core.training"))
    .onChange(of: startRequested, initial: true) { _, requested in
      guard requested else { return }
      // Consume the intent before navigating. The list's initial callback can run again
      // when a completed workout dismisses back to it.
      startRequested = false
      if let activeWorkout { selectedWorkout = activeWorkout } else { presentedSheet = .start }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(L10n.text("core.start.workout"), systemImage: "plus") {
          presentedSheet = .start
        }
        .disabled(activeWorkout != nil)
        .accessibilityIdentifier("training.start")
      }
    }
    .navigationDestination(item: $selectedWorkout) { ActiveWorkoutView(workout: $0) }
    .sheet(
      item: $presentedSheet,
      onDismiss: {
        if let queuedWorkout {
          selectedWorkout = queuedWorkout
          self.queuedWorkout = nil
        }
      }
    ) { sheet in
      switch sheet {
      case .start:
        StartWorkoutSheet { queuedWorkout = $0 }
      }
    }
    .alert(L10n.text("core.delete.this.workout"), isPresented: deletionAlertBinding, presenting: pendingDeletion) { workout in
      Button(L10n.text("core.delete"), role: .destructive) {
        modelContext.delete(workout)
        do { try modelContext.save() } catch {
          modelContext.rollback()
          saveError = L10n.Message(resolving: { error.localizedDescription })
        }
        pendingDeletion = nil
      }
      Button(L10n.text("core.cancel"), role: .cancel) { pendingDeletion = nil }
    } message: { _ in
      Text(L10n.text("core.exercises.and.sets.will.also.be.deleted.this.cannot.be.undone"))
    }
    .alert(
      L10n.text("core.save.failed"), isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
    ) {
      Button(L10n.text("core.ok"), role: .cancel) {}
    } message: {
      Text(saveError?.text ?? L10n.text("core.please.try.again"))
    }
  }

  private var deletionAlertBinding: Binding<Bool> {
    Binding(
      get: { pendingDeletion != nil },
      set: { if !$0 { pendingDeletion = nil } }
    )
  }
}

private struct StartWorkoutSheet: View {
  let onStarted: (Workout) -> Void
  @State private var saveError: L10n.Message?
  @Query private var existingWorkouts: [Workout]
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \Routine.updatedAt, order: .reverse)
  private var routines: [Routine]

  var body: some View {
    NavigationStack {
      List {
        Section {
          Button {
            start(from: nil)
          } label: {
            Label(L10n.text("recording.start.directly"), systemImage: "square.and.pencil")
          }
          .accessibilityIdentifier("training.startBlank")
        }

        if !routines.isEmpty {
          Section(L10n.text("core.my.routines")) {
            ForEach(routines) { routine in
              Button {
                start(from: routine)
              } label: {
                VStack(alignment: .leading, spacing: 3) {
                  Text(routine.name)
                  Text(L10n.text("core.exercises", routine.exercises.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              .accessibilityIdentifier("training.startRoutine.\(routine.id.uuidString)")
            }
          }
        }
      }
      .navigationTitle(L10n.text("core.start.workout"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("core.cancel")) { dismiss() }
        }
      }
      .alert(
        L10n.text("core.cannot.start.workout"),
        isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
      ) {
        Button(L10n.text("core.ok"), role: .cancel) {}
      } message: {
        Text(saveError?.text ?? L10n.text("core.please.try.again"))
      }
    }
  }

  private func start(from routine: Routine?) {
    if let active = existingWorkouts.first(where: { $0.status == .inProgress }) {
      onStarted(active)
      dismiss()
      return
    }
    if let routine, !routine.exercises.allSatisfy(\.hasValidDefaults) {
      saveError = L10n.Message(resolving: { L10n.text("core.this.routine.has.invalid.values.edit.it.in.the.library.first") })
      return
    }
    let workout = RoutineFactory.workout(from: routine)
    modelContext.insert(workout)
    do {
      try modelContext.save()
      onStarted(workout)
      dismiss()
    } catch {
      modelContext.rollback()
      saveError = L10n.Message(resolving: { error.localizedDescription })
    }
  }
}

struct WorkoutRow: View {
  let workout: Workout

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(workout.title)
          .font(.body.weight(.semibold))
        Spacer()
        Text(workout.status.title)
          .font(.caption.weight(.medium))
          .foregroundStyle(workout.status == .completed ? .green : .orange)
      }
      Text(workout.startedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(L10n.text("core.exercises", workout.exercises.count))
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 2)
  }
}

struct WorkoutDetailView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \Workout.startedAt, order: .reverse) private var history: [Workout]
  let workout: Workout
  @State private var editing = false
  @State private var repeatedWorkout: Workout?
  @State private var message: L10n.Message?
  @State private var templateSaved = false

  var body: some View {
    List {
      Section {
        Button(L10n.text("core.train.again"), systemImage: "repeat", action: repeatWorkout)
          .disabled(history.contains { $0.status == .inProgress })
          .accessibilityIdentifier("training.repeat")
        Button(
          templateSaved ? L10n.text("core.saved.as.a.routine") : L10n.text("core.save.as.a.routine"), systemImage: "list.bullet.rectangle",
          action: saveAsTemplate
        )
        .disabled(templateSaved).accessibilityIdentifier("training.saveTemplate")
      }
      let records = WorkoutInsights.personalRecords(for: workout, history: history)
      if !records.isEmpty {
        Section(L10n.text("core.personal.records")) {
          ForEach(records) { record in
            VStack(alignment: .leading, spacing: 5) {
              Label("\(record.exerciseName) · \(record.title)", systemImage: "trophy.fill")
              Text(
                "\(record.previousValue.formatted(.number.locale(L10n.locale))) → \(record.value.formatted(.number.locale(L10n.locale))) \(record.unit)"
              )
              .font(.subheadline).monospacedDigit()
            }
          }
        }
      }
      Section(L10n.text("core.workout.details")) {
        LabeledContent(
          L10n.text("core.start"), value: workout.startedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))
        if let endedAt = workout.endedAt {
          LabeledContent(L10n.text("core.end"), value: endedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))
        }
        LabeledContent(L10n.text("core.status"), value: workout.status.title)
        LabeledContent(L10n.text("core.completed.sets"), value: L10n.text("core.sets", WorkoutInsights.completedSets(in: workout)))
        LabeledContent(L10n.text("core.training.volume"), value: L10n.text("core.kg.reps" , String(describing: WorkoutInsights.volume(in: workout).formatted(.number.locale(L10n.locale)))))
        if !workout.notes.isEmpty { Text(workout.notes) }
      }
      ForEach(workout.sortedExercises) { exercise in
        Section(exercise.displayName) {
          Text(exercise.trackingMode.title).font(.caption).foregroundStyle(.secondary)
          if exercise.trackingMode.usesSets {
            ForEach(exercise.sortedStrengthSets) { set in
              HStack {
                Text(L10n.text("core.set", set.orderIndex + 1))
                Spacer()
                Text(WorkoutValueFormatting.set(set, mode: exercise.trackingMode)).monospacedDigit()
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(set.isCompleted ? Color.green : Color.secondary)
                  .accessibilityLabel(set.isCompleted ? L10n.text("core.completed") : L10n.text("core.incomplete"))
              }
            }
          } else {
            ForEach(exercise.cardioEntries) { cardio in
              LabeledContent(
                L10n.text("core.duration"), value: L10n.text("core.min.sec" , String(describing: cardio.durationSeconds / 60), String(describing: cardio.durationSeconds % 60)))
              if cardio.distanceKilometers > 0 {
                LabeledContent(L10n.text("core.distance"), value: "\(cardio.distanceKilometers.formatted(.number.locale(L10n.locale))) km")
              }
              if cardio.calories > 0 {
                LabeledContent(L10n.text("core.calories.burned"), value: "\(cardio.calories.formatted(.number.locale(L10n.locale))) kcal")
              }
            }
          }
          if !exercise.notes.isEmpty { Text(exercise.notes).font(.footnote) }
        }
      }
    }
    .navigationTitle(workout.title).navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(L10n.text("core.edit")) { editing = true }.accessibilityIdentifier("training.edit")
      }
    }
    .sheet(isPresented: $editing) { WorkoutHistoryEditor(original: workout) }
    .navigationDestination(item: $repeatedWorkout) { ActiveWorkoutView(workout: $0) }
    .alert(L10n.text("core.action.failed"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }))
    {
      Button(L10n.text("core.ok"), role: .cancel) {}
    } message: {
      Text(message?.text ?? L10n.text("core.please.try.again"))
    }
  }

  private func repeatWorkout() {
    guard !history.contains(where: { $0.status == .inProgress }) else { return }
    let copy = WorkoutHistoryFactory.copy(of: workout, startedAt: .now, status: .inProgress)
    modelContext.insert(copy)
    do {
      try modelContext.save()
      repeatedWorkout = copy
    } catch {
      modelContext.rollback()
      message = L10n.Message(resolving: { error.localizedDescription })
    }
  }
  private func saveAsTemplate() {
    let routine = WorkoutHistoryFactory.routine(from: workout)
    modelContext.insert(routine)
    do {
      try modelContext.save()
      templateSaved = true
    } catch {
      modelContext.rollback()
      message = L10n.Message(resolving: { error.localizedDescription })
    }
  }
}

private struct WorkoutHistoryEditor: View {
  @Environment(\.modelContext) private var modelContext
  let original: Workout
  @State private var draft: Workout
  init(original: Workout) {
    self.original = original
    _draft = State(
      initialValue: WorkoutHistoryFactory.copy(
        of: original, startedAt: original.startedAt, status: .completed, preserveCompletion: true))
  }
  var body: some View {
    NavigationStack {
      ActiveWorkoutView(workout: draft, isHistoricalEdit: true) {
        try WorkoutHistoryFactory.apply(draft, to: original, context: modelContext)
      }
    }
  }
}
