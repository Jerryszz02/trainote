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
      if newValue > 0, activeWorkout == nil {
        presentedSheet = .start
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
    .sheet(item: $presentedSheet) { sheet in
      switch sheet {
      case .start:
        StartWorkoutSheet()
      }
    }
    .alert("删除这条训练记录？", isPresented: deletionAlertBinding, presenting: pendingDeletion) { workout in
      Button("删除", role: .destructive) {
        modelContext.delete(workout)
        try? modelContext.save()
        pendingDeletion = nil
      }
      Button("取消", role: .cancel) { pendingDeletion = nil }
    } message: { _ in
      Text("训练动作和组记录会一起删除，此操作无法撤销。")
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

        Section("我的 Routine") {
          if routines.isEmpty {
            Text("还没有 routine，可在资料库中创建。")
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
    }
  }

  private func start(from routine: Routine?) {
    let workout = RoutineFactory.workout(from: routine)
    modelContext.insert(workout)
    try? modelContext.save()
    dismiss()
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
  let workout: Workout

  var body: some View {
    List {
      Section {
        LabeledContent(
          "开始", value: workout.startedAt.formatted(date: .abbreviated, time: .shortened))
        if let endedAt = workout.endedAt {
          LabeledContent("结束", value: endedAt.formatted(date: .omitted, time: .shortened))
        }
        LabeledContent("状态", value: workout.status.title)
      }

      ForEach(workout.sortedExercises) { exercise in
        Section {
          if exercise.trackingMode == .strength {
            ForEach(exercise.sortedStrengthSets, id: \.id) { strengthSet in
              strengthSetRow(strengthSet)
            }
          } else {
            ForEach(exercise.cardioEntries, id: \.id) { cardio in
              cardioEntryRows(cardio)
            }
          }
        } header: {
          VStack(alignment: .leading) {
            Text(exercise.nameZhSnapshot)
            Text(exercise.nameEnSnapshot)
              .textCase(nil)
              .font(.caption)
          }
        }
      }
    }
    .navigationTitle(workout.title)
    .navigationBarTitleDisplayMode(.inline)
  }

  private func cardioEntryRows(_ cardio: CardioEntry) -> some View {
    let duration = "\(cardio.durationSeconds / 60) 分钟"
    let distance = cardio.distanceKilometers.formatted(
      .number.precision(.fractionLength(0...2))) + " km"
    let calories = cardio.calories.formatted(
      .number.precision(.fractionLength(0))) + " kcal"

    return Group {
      LabeledContent("时长", value: duration)
      if cardio.distanceKilometers > 0 {
        LabeledContent("距离", value: distance)
      }
      if cardio.calories > 0 {
        LabeledContent("消耗", value: calories)
      }
    }
  }

  private func strengthSetRow(_ strengthSet: StrengthSet) -> some View {
    let formattedWeight = strengthSet.weightKilograms.formatted(
      .number.precision(.fractionLength(0...1)))

    return HStack {
      Text("第 \(strengthSet.orderIndex + 1) 组")
      Spacer()
      Text("\(formattedWeight) kg × \(strengthSet.repetitions)")
        .monospacedDigit()
      Image(systemName: strengthSet.isCompleted ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(strengthSet.isCompleted ? Color.green : Color.secondary)
    }
  }
}
