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
  @State private var message: String?
  @AppStorage("training.restSeconds") private var restDuration = 90

  var body: some View {
    List {
      Section("训练信息") {
        TextField("训练名称", text: $workout.title).accessibilityIdentifier("workout.title")
        TextField("备注（可选）", text: $workout.notes, axis: .vertical)
        if isHistoricalEdit {
          DatePicker("开始时间", selection: $workout.startedAt, in: ...Date.now)
          DatePicker(
            "结束时间",
            selection: Binding(
              get: { workout.endedAt ?? workout.startedAt }, set: { workout.endedAt = $0 }),
            in: workout.startedAt...max(workout.startedAt, Date.now))
        } else {
          LabeledContent("已用时") {
            Text(workout.startedAt, style: .timer).monospacedDigit()
          }
        }
      }
      if !isHistoricalEdit {
        Section("组间休息") {
          Picker("完成组后休息", selection: $restDuration) {
            Text("60 秒").tag(60)
            Text("90 秒").tag(90)
            Text("120 秒").tag(120)
          }.pickerStyle(.segmented)
          if let end = workout.restEndsAt {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
              let remaining = max(Int(end.timeIntervalSince(timeline.date).rounded(.up)), 0)
              HStack {
                Label(remaining > 0 ? "休息中" : "休息结束", systemImage: "timer")
                Spacer()
                Text("\(remaining) 秒").monospacedDigit().accessibilityIdentifier(
                  "workout.restRemaining")
              }
            }
            HStack {
              Button("+30 秒") { workout.restEndsAt = max(end, .now).addingTimeInterval(30) }
              Spacer()
              Button("结束休息") { workout.restEndsAt = nil }
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
        Button("添加动作", systemImage: "plus.circle.fill") { showingPicker = true }
          .accessibilityIdentifier("workout.addExercise")
      }
      if !isHistoricalEdit {
        Section {
          Button("放弃这场训练", role: .destructive) { showingDiscard = true }
            .accessibilityIdentifier("workout.discard")
        }
      }
    }
    .navigationTitle(isHistoricalEdit ? "编辑训练" : "进行中")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button(isHistoricalEdit ? "保存" : "完成", action: finish).accessibilityIdentifier(
          "workout.finish")
      }
      if isHistoricalEdit {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }.accessibilityIdentifier("workout.edit.cancel")
        }
      }
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("收起键盘") {
          UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
      }
    }
    .sheet(isPresented: $showingPicker) {
      ExercisePickerView(title: "添加训练动作") { item in
        let exercise = RoutineFactory.workoutExercise(
          from: item, orderIndex: workout.exercises.count)
        exercise.workout = workout
        workout.exercises.append(exercise)
      }
    }
    .confirmationDialog("放弃这场训练？", isPresented: $showingDiscard, titleVisibility: .visible) {
      Button("放弃并删除", role: .destructive, action: discard)
      Button("继续训练", role: .cancel) {}
    }
    .alert(
      "请检查记录", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    ) {
      if !isHistoricalEdit { Button("重试保存") { persist() } }
      Button("知道了", role: .cancel) { message = nil }
    } message: {
      Text(message ?? "请重试。")
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
      message = "记录尚未保存。输入仍保留，请重试。\(error.localizedDescription)"
    }
  }

  private func finish() {
    if let invalid = workout.validationMessage {
      message = invalid
      return
    }
    if isHistoricalEdit {
      guard let end = workout.endedAt, end >= workout.startedAt else {
        message = "结束时间不能早于开始时间。"
        return
      }
      do {
        try saveHistory?()
        dismiss()
      } catch { message = "修改未能保存，请重试。\(error.localizedDescription)" }
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
      message = "训练未能完成保存，请重试。\(error.localizedDescription)"
    }
  }

  private func discard() {
    modelContext.delete(workout)
    do {
      try modelContext.save()
      dismiss()
    } catch {
      modelContext.rollback()
      message = "删除失败，记录仍保留。\(error.localizedDescription)"
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
  let reportError: (String) -> Void
  let onDelete: () -> Void
  @State private var pendingMode: TrackingMode?
  @State private var confirmingMode = false
  @State private var confirmingPrevious = false
  @State private var confirmingDelete = false

  private var previous: WorkoutExercise? {
    WorkoutInsights.previousExercise(for: exercise, before: workout, history: history)
  }

  var body: some View {
    Section {
      Picker(
        "记录方式",
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
          Text("上次表现").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
          if previous.trackingMode.usesSets {
            ForEach(
              previous.sortedStrengthSets.filter {
                $0.isCompleted && $0.isValid(for: previous.trackingMode)
              }
            ) { set in
              Text(
                "第 \(set.orderIndex + 1) 组：\(WorkoutValueFormatting.set(set, mode: previous.trackingMode))"
              )
              .font(.caption).monospacedDigit()
            }
          } else if let cardio = previous.cardioEntries.first(where: { $0.isValid }) {
            Text("\(cardio.durationSeconds / 60) 分钟 · \(cardio.distanceKilometers.formatted()) km")
              .font(.caption)
          }
          Button("沿用上次完成数据") { confirmingPrevious = true }
            .accessibilityIdentifier("exercise.history.apply.\(exercise.id.uuidString)")
        }
      }
      if exercise.trackingMode.usesSets {
        ForEach(exercise.sortedStrengthSets) { set in
          StrengthSetRow(strengthSet: set, mode: exercise.trackingMode) {
            if !set.isCompleted && !set.isValid(for: exercise.trackingMode) {
              reportError("请先填写有效的\(exercise.trackingMode == .duration ? "时长" : "次数和重量")。")
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
        Button("增加一组", systemImage: "plus") { addSet() }
      } else if let cardio = exercise.cardioEntries.first {
        CardioEntryEditor(cardio: cardio)
      }
      TextField("动作备注（可选）", text: $exercise.notes, axis: .vertical)
      Button("移除动作", role: .destructive) { confirmingDelete = true }
    } header: {
      VStack(alignment: .leading, spacing: 3) {
        Text(exercise.nameZhSnapshot)
        Text(exercise.nameEnSnapshot).font(.caption).textCase(nil)
      }
    }
    .confirmationDialog("切换记录方式？", isPresented: $confirmingMode, titleVisibility: .visible) {
      Button("切换") { applyMode() }
      Button("取消", role: .cancel) { pendingMode = nil }
    } message: {
      Text("会保留各方式已填写的数值，并重置组的完成状态。请确认当前方式的实际完成数据。")
    }
    .confirmationDialog("用上次数据替换当前参数？", isPresented: $confirmingPrevious, titleVisibility: .visible)
    {
      Button("沿用并重置完成状态") { copyPrevious() }
      Button("取消", role: .cancel) {}
    } message: {
      Text("复制后的组需要重新标记完成。")
    }
    .confirmationDialog("移除这个动作和已记录的组？", isPresented: $confirmingDelete, titleVisibility: .visible)
    {
      Button("移除动作", role: .destructive, action: onDelete)
      Button("取消", role: .cancel) {}
    }
  }

  private func addSet() {
    let last = exercise.sortedStrengthSets.last
    let set = StrengthSet(
      orderIndex: exercise.strengthSets.count, weightKilograms: last?.weightKilograms ?? 0,
      repetitions: last?.repetitions ?? 8, durationSeconds: last?.durationSeconds ?? 30)
    set.exercise = exercise
    exercise.strengthSets.append(set)
  }

  private func applyMode() {
    guard let mode = pendingMode else { return }
    exercise.trackingMode = mode
    for set in exercise.strengthSets { set.isCompleted = false }
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
          durationSeconds: old.durationSeconds)
        set.exercise = exercise
        return set
      }
      if !isDraft { oldSets.forEach { modelContext.delete($0) } }
    } else if let old = previous.cardioEntries.first(where: { $0.isValid }),
      let cardio = exercise.cardioEntries.first
    {
      cardio.durationSeconds = old.durationSeconds
      cardio.distanceKilometers = old.distanceKilometers
      cardio.calories = old.calories
    }
  }
}

private struct StrengthSetRow: View {
  @Bindable var strengthSet: StrengthSet
  let mode: TrackingMode
  let onComplete: () -> Void
  let onDelete: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Button(action: onComplete) {
          Label(
            "第 \(strengthSet.orderIndex + 1) 组",
            systemImage: strengthSet.isCompleted ? "checkmark.circle.fill" : "circle"
          )
          .foregroundStyle(strengthSet.isCompleted ? Color.green : Color.primary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(
          "第 \(strengthSet.orderIndex + 1) 组，\(strengthSet.isCompleted ? "已完成" : "标记完成")"
        )
        .accessibilityIdentifier("strengthSet.complete.\(strengthSet.id.uuidString)")
        Spacer()
        Button("删除组", systemImage: "trash", role: .destructive, action: onDelete)
          .labelStyle(.iconOnly).buttonStyle(.borderless)
      }
      if mode == .strength {
        HStack {
          Button {
            strengthSet.weightKilograms = max(strengthSet.weightKilograms - 2.5, 0)
          } label: {
            Image(systemName: "minus.circle")
          }
          .accessibilityLabel("减重 2.5 公斤").buttonStyle(.borderless)
          TextField(
            "重量", value: $strengthSet.weightKilograms,
            format: .number.precision(.fractionLength(0...2))
          )
          .keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel("重量")
          .accessibilityIdentifier("strengthSet.weight.\(strengthSet.id.uuidString)")
          Text("kg").foregroundStyle(.secondary)
          Button {
            strengthSet.weightKilograms = min(strengthSet.weightKilograms + 2.5, 10_000)
          } label: {
            Image(systemName: "plus.circle")
          }
          .accessibilityLabel("加重 2.5 公斤").buttonStyle(.borderless)
        }
      }
      HStack {
        Text(mode == .duration ? "时长" : "次数")
        Spacer()
        TextField(
          mode == .duration ? "秒数" : "次数",
          value: mode == .duration ? $strengthSet.durationSeconds : $strengthSet.repetitions,
          format: .number
        )
        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
        .accessibilityLabel(mode == .duration ? "时长秒数" : "次数")
        .accessibilityIdentifier(
          "strengthSet.\(mode == .duration ? "duration" : "repetitions").\(strengthSet.id.uuidString)"
        )
        Text(mode == .duration ? "秒" : "次").foregroundStyle(.secondary)
      }
    }.padding(.vertical, 5)
  }
}

private struct CardioEntryEditor: View {
  @Bindable var cardio: CardioEntry
  var body: some View {
    LabeledContent("时长（分钟）") {
      TextField("0", value: durationMinutes, format: .number.precision(.fractionLength(0...1)))
        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier(
          "cardio.duration")
    }
    LabeledContent("距离（km，可选）") {
      TextField(
        "0", value: $cardio.distanceKilometers, format: .number.precision(.fractionLength(0...2))
      )
      .keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel("距离公里")
    }
    LabeledContent("消耗（kcal，可选）") {
      TextField("0", value: $cardio.calories, format: .number.precision(.fractionLength(0...1)))
        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel("消耗千卡")
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
        "\(set.weightKilograms.formatted(.number.precision(.fractionLength(0...2)))) kg × \(set.repetitions) 次"
    case .repetitions: return "\(set.repetitions) 次"
    case .duration: return "\(set.durationSeconds) 秒"
    case .cardio: return "有氧"
    }
  }
}
