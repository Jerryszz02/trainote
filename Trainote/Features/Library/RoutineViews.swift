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

  @State private var presentation: RoutinePresentation?
  @State private var pendingDeletion: Routine?
  @State private var deletionError: String?

  var body: some View {
    List {
      if routines.isEmpty {
        ContentUnavailableView(
          "还没有训练模板",
          systemImage: "list.bullet.rectangle",
          description: Text("把常用动作和默认训练参数保存成一套模板。")
        )
      } else {
        ForEach(routines) { routine in
          Button {
            presentation = RoutinePresentation(
              routine: draft(of: routine), original: routine, isNew: false)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(routine.name).font(.body.weight(.medium))
                Text("\(routine.exercises.count) 个动作")
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
          .swipeActions {
            Button("删除", role: .destructive) { pendingDeletion = routine }
          }
        }
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("新建训练模板", systemImage: "plus") { createRoutine() }
          .accessibilityIdentifier("routine.create")
      }
    }
    .sheet(item: $presentation) { value in
      RoutineEditorView(routine: value.routine, original: value.original, isNew: value.isNew)
    }
    .alert("删除这个训练模板？", isPresented: deletionAlertBinding, presenting: pendingDeletion) {
      routine in
      Button("删除", role: .destructive) {
        modelContext.delete(routine)
        do { try modelContext.save() } catch {
          modelContext.rollback()
          deletionError = error.localizedDescription
        }
        pendingDeletion = nil
      }
      Button("取消", role: .cancel) { pendingDeletion = nil }
    } message: { _ in
      Text("已经完成或正在进行的训练不会受到影响。")
    }
    .alert(
      "删除失败",
      isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })
    ) {
      Button("知道了", role: .cancel) {}
    } message: {
      Text(deletionError ?? "请重试。")
    }
  }

  private var deletionAlertBinding: Binding<Bool> {
    Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
  }

  private func createRoutine() {
    let routine = Routine(name: "新训练模板")
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
  @State private var saveError: String?

  private var canSave: Bool {
    !routine.name.trimmed.isEmpty && !routine.exercises.isEmpty
      && routine.exercises.allSatisfy(\.hasValidDefaults)
  }

  var body: some View {
    NavigationStack {
      List {
        Section("基本信息") {
          TextField("模板名称", text: $routine.name)
            .accessibilityIdentifier("routine.name")
          TextField("备注（可选）", text: $routine.notes, axis: .vertical)
        }

        Section("动作") {
          if routine.exercises.isEmpty {
            Text("还没有动作。")
              .foregroundStyle(.secondary)
          }
          ForEach(routine.sortedExercises) { exercise in
            RoutineExerciseEditor(exercise: exercise) {
              delete(exercise)
            }
          }
          .onMove(perform: move)

          Button("添加动作", systemImage: "plus.circle.fill") {
            presentedSheet = .exercisePicker
          }
          .accessibilityIdentifier("routine.addExercise")
        }
      }
      .environment(\.editMode, .constant(.active))
      .navigationTitle(isNew ? "新建训练模板" : "编辑训练模板")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(isNew ? "取消" : "关闭") {
            if isNew { showCancelConfirmation = true } else { dismiss() }
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存", action: save)
            .disabled(!canSave)
            .accessibilityIdentifier("routine.save")
        }
      }
      .toolbar { NutritionKeyboardDoneToolbar() }
      .sheet(item: $presentedSheet) { sheet in
        switch sheet {
        case .exercisePicker:
          ExercisePickerView(title: "添加模板动作") { item in
            add(item)
          }
        }
      }
      .alert(
        "无法保存训练模板",
        isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
      ) {
        Button("知道了", role: .cancel) {}
      } message: {
        Text(saveError ?? "请稍后重试。")
      }
      .confirmationDialog(
        "放弃新训练模板？", isPresented: $showCancelConfirmation, titleVisibility: .visible
      ) {
        Button("放弃", role: .destructive) {
          dismiss()
        }
        Button("继续编辑", role: .cancel) {}
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
      saveError = error.localizedDescription
    }
  }
}

private struct RoutineExerciseEditor: View {
  @Bindable var exercise: RoutineExercise
  let onDelete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading) {
          Text(exercise.nameZhSnapshot).font(.body.weight(.medium))
          Text(exercise.nameEnSnapshot).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
          .labelStyle(.iconOnly)
      }

      Picker("记录方式", selection: $exercise.trackingMode) {
        ForEach(TrackingMode.allCases) { Text($0.title).tag($0) }
      }
      .accessibilityIdentifier("routine.mode.\(exercise.id.uuidString)")

      if exercise.trackingMode == .strength {
        HStack {
          numberField("组", value: $exercise.defaultSetCount)
          numberField("次", value: $exercise.defaultRepetitions)
          LabeledContent("kg") {
            TextField(
              "0", value: $exercise.defaultWeightKilograms,
              format: .number.precision(.fractionLength(0...2))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 70)
          }
        }
      } else if exercise.trackingMode == .repetitions {
        numberField("组数", value: $exercise.defaultSetCount)
        numberField("次数", value: $exercise.defaultRepetitions)
      } else if exercise.trackingMode == .duration {
        numberField("组数", value: $exercise.defaultSetCount)
        numberField("每组秒数", value: $exercise.defaultDurationSeconds)
      } else {
        LabeledContent("默认时长") {
          HStack {
            TextField(
              "0", value: durationMinutes, format: .number.precision(.fractionLength(0...1))
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            Text("分钟").foregroundStyle(.secondary)
          }
        }
        LabeledContent("默认距离") {
          HStack {
            TextField(
              "0", value: $exercise.defaultDistanceKilometers,
              format: .number.precision(.fractionLength(0...2))
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
      TextField("0", value: value, format: .number)
        .keyboardType(.numberPad)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 48)
    }
  }
}
