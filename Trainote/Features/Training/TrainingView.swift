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
  @State private var saveError: String?

  let startRequest: Int

  private var activeWorkout: Workout? {
    workouts.first { $0.status == .inProgress }
  }

  private var completedWorkouts: [Workout] {
    workouts.filter { $0.status == .completed }
  }

  var body: some View {
    List {
      if let activeWorkout {
        Section("进行中") {
          NavigationLink {
            ActiveWorkoutView(workout: activeWorkout)
          } label: {
            WorkoutRow(workout: activeWorkout)
          }
          .accessibilityIdentifier("training.activeWorkout")
        }
      }

      Section("历史") {
        if completedWorkouts.isEmpty {
          ContentUnavailableView(
            "还没有完成的训练",
            systemImage: "figure.strengthtraining.traditional",
            description: Text("点击右上角加号开始第一场训练。")
          )
          .frame(maxWidth: .infinity)
        } else {
          ForEach(completedWorkouts) { workout in
            NavigationLink {
              WorkoutDetailView(workout: workout)
            } label: {
              WorkoutRow(workout: workout)
            }
            .swipeActions {
              Button("删除", role: .destructive) {
                pendingDeletion = workout
              }
            }
          }
        }
      }
    }
    .navigationTitle("训练")
    .onChange(of: startRequest, initial: true) { _, newValue in
      if newValue > 0 {
        if let activeWorkout { selectedWorkout = activeWorkout } else { presentedSheet = .start }
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("开始训练", systemImage: "plus") {
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
    .alert("删除这条训练记录？", isPresented: deletionAlertBinding, presenting: pendingDeletion) { workout in
      Button("删除", role: .destructive) {
        modelContext.delete(workout)
        do { try modelContext.save() } catch {
          modelContext.rollback()
          saveError = error.localizedDescription
        }
        pendingDeletion = nil
      }
      Button("取消", role: .cancel) { pendingDeletion = nil }
    } message: { _ in
      Text("训练动作和组记录会一起删除，此操作无法撤销。")
    }
    .alert(
      "保存失败", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
    ) {
      Button("知道了", role: .cancel) {}
    } message: {
      Text(saveError ?? "请重试。")
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
  @State private var saveError: String?
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
            Label("空白训练", systemImage: "square.and.pencil")
          }
          .accessibilityIdentifier("training.startBlank")
        }

        Section("我的训练模板") {
          if routines.isEmpty {
            Text("还没有训练模板，可在资料库中创建。")
              .foregroundStyle(.secondary)
          } else {
            ForEach(routines) { routine in
              Button {
                start(from: routine)
              } label: {
                VStack(alignment: .leading, spacing: 3) {
                  Text(routine.name)
                  Text("\(routine.exercises.count) 个动作")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              .accessibilityIdentifier("training.startRoutine.\(routine.id.uuidString)")
            }
          }
        }
      }
      .navigationTitle("开始训练")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
      }
      .alert(
        "无法开始训练",
        isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
      ) {
        Button("知道了", role: .cancel) {}
      } message: {
        Text(saveError ?? "请重试。")
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
      saveError = "模板包含无效参数，请先在资料库中编辑修正。"
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
      saveError = error.localizedDescription
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
      Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened))
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("\(workout.exercises.count) 个动作")
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
  @State private var message: String?
  @State private var templateSaved = false

  var body: some View {
    List {
      Section {
        Button("再次训练", systemImage: "repeat", action: repeatWorkout)
          .disabled(history.contains { $0.status == .inProgress })
          .accessibilityIdentifier("training.repeat")
        Button(
          templateSaved ? "已保存为训练模板" : "保存为训练模板", systemImage: "list.bullet.rectangle",
          action: saveAsTemplate
        )
        .disabled(templateSaved).accessibilityIdentifier("training.saveTemplate")
      }
      let records = WorkoutInsights.personalRecords(for: workout, history: history)
      if !records.isEmpty {
        Section("突破 PR") {
          ForEach(records) { record in
            VStack(alignment: .leading, spacing: 5) {
              Label("\(record.exerciseName) · \(record.title)", systemImage: "trophy.fill")
              Text(
                "\(record.previousValue.formatted()) → \(record.value.formatted()) \(record.unit)"
              )
              .font(.subheadline).monospacedDigit()
            }
          }
        }
      }
      Section("训练信息") {
        LabeledContent(
          "开始", value: workout.startedAt.formatted(date: .abbreviated, time: .shortened))
        if let endedAt = workout.endedAt {
          LabeledContent("结束", value: endedAt.formatted(date: .abbreviated, time: .shortened))
        }
        LabeledContent("状态", value: workout.status.title)
        LabeledContent("完成组数", value: "\(WorkoutInsights.completedSets(in: workout)) 组")
        LabeledContent("负重容量", value: "\(WorkoutInsights.volume(in: workout).formatted()) kg·次")
        if !workout.notes.isEmpty { Text(workout.notes) }
      }
      ForEach(workout.sortedExercises) { exercise in
        Section(exercise.nameZhSnapshot) {
          Text(exercise.trackingMode.title).font(.caption).foregroundStyle(.secondary)
          if exercise.trackingMode.usesSets {
            ForEach(exercise.sortedStrengthSets) { set in
              HStack {
                Text("第 \(set.orderIndex + 1) 组")
                Spacer()
                Text(WorkoutValueFormatting.set(set, mode: exercise.trackingMode)).monospacedDigit()
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(set.isCompleted ? Color.green : Color.secondary)
                  .accessibilityLabel(set.isCompleted ? "已完成" : "未完成")
              }
            }
          } else {
            ForEach(exercise.cardioEntries) { cardio in
              LabeledContent(
                "时长", value: "\(cardio.durationSeconds / 60) 分 \(cardio.durationSeconds % 60) 秒")
              if cardio.distanceKilometers > 0 {
                LabeledContent("距离", value: "\(cardio.distanceKilometers.formatted()) km")
              }
              if cardio.calories > 0 {
                LabeledContent("消耗", value: "\(cardio.calories.formatted()) kcal")
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
        Button("编辑") { editing = true }.accessibilityIdentifier("training.edit")
      }
    }
    .sheet(isPresented: $editing) { WorkoutHistoryEditor(original: workout) }
    .navigationDestination(item: $repeatedWorkout) { ActiveWorkoutView(workout: $0) }
    .alert("操作失败", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }))
    {
      Button("知道了", role: .cancel) {}
    } message: {
      Text(message ?? "请重试。")
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
      message = error.localizedDescription
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
      message = error.localizedDescription
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
