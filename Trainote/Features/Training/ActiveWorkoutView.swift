import SwiftData
import SwiftUI

private enum ActiveWorkoutSheet: String, Identifiable {
  case exercisePicker

  var id: String { rawValue }
}

struct ActiveWorkoutView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @Bindable var workout: Workout
  @State private var presentedSheet: ActiveWorkoutSheet?
  @State private var showingDiscardConfirmation = false
  @State private var validationMessage: String?

  var body: some View {
    List {
      Section("训练信息") {
        TextField("训练名称", text: $workout.title)
        TextField("备注（可选）", text: $workout.notes, axis: .vertical)
      }

      ForEach(workout.sortedExercises) { exercise in
        WorkoutExerciseEditor(exercise: exercise) {
          delete(exercise)
        }
      }

      Section {
        Button {
          presentedSheet = .exercisePicker
        } label: {
          Label("添加动作", systemImage: "plus.circle.fill")
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("workout.addExercise")
      }
    }
    .navigationTitle("进行中")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("完成", action: finish)
          .accessibilityIdentifier("workout.finish")
      }
      ToolbarItem(placement: .topBarLeading) {
        Button("放弃", role: .destructive) {
          showingDiscardConfirmation = true
        }
      }
    }
    .sheet(item: $presentedSheet) { sheet in
      switch sheet {
      case .exercisePicker:
        ExercisePickerView(title: "添加训练动作") { item in
          add(item)
        }
      }
    }
    .confirmationDialog(
      "放弃这场训练？", isPresented: $showingDiscardConfirmation, titleVisibility: .visible
    ) {
      Button("放弃并删除", role: .destructive, action: discard)
      Button("继续训练", role: .cancel) {}
    } message: {
      Text("这场训练的动作和组记录会被删除。")
    }
    .alert("暂时无法完成训练", isPresented: validationAlertBinding) {
      Button("知道了", role: .cancel) { validationMessage = nil }
    } message: {
      Text(validationMessage ?? "请至少完成一个力量组或填写一条有效有氧记录。")
    }
  }

  private var validationAlertBinding: Binding<Bool> {
    Binding(
      get: { validationMessage != nil },
      set: { if !$0 { validationMessage = nil } }
    )
  }

  private func add(_ item: ExerciseCatalogItem) {
    let exercise = RoutineFactory.workoutExercise(
      from: item,
      orderIndex: workout.exercises.count
    )
    exercise.workout = workout
    workout.exercises.append(exercise)
    try? modelContext.save()
  }

  private func delete(_ exercise: WorkoutExercise) {
    modelContext.delete(exercise)
    for (index, item) in workout.sortedExercises.filter({ $0.id != exercise.id }).enumerated() {
      item.orderIndex = index
    }
    try? modelContext.save()
  }

  private func finish() {
    guard !workout.title.trimmed.isEmpty else {
      validationMessage = "请输入训练名称。"
      return
    }
    guard workout.hasValidResult else {
      validationMessage = "请至少完成一个力量组，或填写一条时长大于 0 的有氧记录。"
      return
    }
    workout.status = .completed
    workout.endedAt = .now
    try? modelContext.save()
    dismiss()
  }

  private func discard() {
    modelContext.delete(workout)
    try? modelContext.save()
    dismiss()
  }
}

private struct WorkoutExerciseEditor: View {
  @Environment(\.modelContext) private var modelContext
  @Bindable var exercise: WorkoutExercise
  let onDelete: () -> Void

  var body: some View {
    Section {
      LabeledContent("记录方式") {
        Label(exercise.trackingMode.title, systemImage: exercise.trackingMode.systemImage)
          .foregroundStyle(.secondary)
      }

      if exercise.trackingMode == .strength {
        ForEach(exercise.sortedStrengthSets) { strengthSet in
          StrengthSetRow(strengthSet: strengthSet) {
            delete(strengthSet)
          }
        }
        Button("增加一组", systemImage: "plus") { addStrengthSet() }
      } else {
        if let cardio = exercise.cardioEntries.first {
          CardioEntryEditor(cardio: cardio)
        } else {
          Button("添加有氧记录", systemImage: "plus") { ensureCardioEntry() }
        }
      }

      TextField("动作备注（可选）", text: $exercise.notes, axis: .vertical)
      Button("移除动作", role: .destructive, action: onDelete)
    } header: {
      VStack(alignment: .leading, spacing: 2) {
        Text(exercise.nameZhSnapshot)
        Text(exercise.nameEnSnapshot)
          .font(.caption)
          .textCase(nil)
      }
    }
  }

  private func addStrengthSet() {
    let previous = exercise.sortedStrengthSets.last
    let strengthSet = StrengthSet(
      orderIndex: exercise.strengthSets.count,
      weightKilograms: previous?.weightKilograms ?? 0,
      repetitions: previous?.repetitions ?? 8
    )
    strengthSet.exercise = exercise
    exercise.strengthSets.append(strengthSet)
  }

  private func delete(_ strengthSet: StrengthSet) {
    modelContext.delete(strengthSet)
    for (index, item) in exercise.sortedStrengthSets.filter({ $0.id != strengthSet.id })
      .enumerated()
    {
      item.orderIndex = index
    }
  }

  private func ensureCardioEntry() {
    guard exercise.cardioEntries.isEmpty else { return }
    let cardio = CardioEntry()
    cardio.exercise = exercise
    exercise.cardioEntries.append(cardio)
  }
}

private struct StrengthSetRow: View {
  @Bindable var strengthSet: StrengthSet
  let onDelete: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Button {
        strengthSet.isCompleted.toggle()
      } label: {
        Image(systemName: strengthSet.isCompleted ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(strengthSet.isCompleted ? .green : .secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(strengthSet.isCompleted ? "标记为未完成" : "标记为完成")
      .accessibilityIdentifier("strengthSet.complete.\(strengthSet.id.uuidString)")

      Text("\(strengthSet.orderIndex + 1)")
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .frame(width: 18)

      TextField(
        "重量", value: $strengthSet.weightKilograms, format: .number.precision(.fractionLength(0...2))
      )
      .keyboardType(.decimalPad)
      .multilineTextAlignment(.trailing)
      Text("kg").foregroundStyle(.secondary)
      Text("×").foregroundStyle(.secondary)
      TextField("次数", value: $strengthSet.repetitions, format: .number)
        .keyboardType(.numberPad)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 54)

      Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
        .labelStyle(.iconOnly)
    }
  }
}

private struct CardioEntryEditor: View {
  @Bindable var cardio: CardioEntry

  var body: some View {
    LabeledContent("时长") {
      HStack {
        TextField("0", value: durationMinutes, format: .number.precision(.fractionLength(0...1)))
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .accessibilityIdentifier("cardio.duration")
        Text("分钟").foregroundStyle(.secondary)
      }
    }
    LabeledContent("距离（可选）") {
      HStack {
        TextField(
          "0", value: $cardio.distanceKilometers, format: .number.precision(.fractionLength(0...2))
        )
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        Text("km").foregroundStyle(.secondary)
      }
    }
    LabeledContent("消耗（可选）") {
      HStack {
        TextField("0", value: $cardio.calories, format: .number.precision(.fractionLength(0...1)))
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
        Text("kcal").foregroundStyle(.secondary)
      }
    }
  }

  private var durationMinutes: Binding<Double> {
    Binding(
      get: { Double(cardio.durationSeconds) / 60 },
      set: { cardio.durationSeconds = max(Int($0 * 60), 0) }
    )
  }
}
