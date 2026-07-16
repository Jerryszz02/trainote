import SwiftData
import SwiftUI

private struct RoutinePresentation: Identifiable {
  let routine: Routine
  let isNew: Bool
  var id: UUID { routine.id }
}

struct RoutinesView: View {
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \Routine.updatedAt, order: .reverse)
  private var routines: [Routine]

  @State private var presentation: RoutinePresentation?
  @State private var pendingDeletion: Routine?

  var body: some View {
    List {
      if routines.isEmpty {
        ContentUnavailableView(
          "还没有 Routine",
          systemImage: "list.bullet.rectangle",
          description: Text("把常用动作和默认训练参数保存成一套模板。")
        )
      } else {
        ForEach(routines) { routine in
          Button {
            presentation = RoutinePresentation(routine: routine, isNew: false)
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
        Button("新建 Routine", systemImage: "plus") { createRoutine() }
          .accessibilityIdentifier("routine.create")
      }
    }
    .sheet(item: $presentation) { value in
      RoutineEditorView(routine: value.routine, isNew: value.isNew)
    }
    .alert("删除这个 Routine？", isPresented: deletionAlertBinding, presenting: pendingDeletion) {
      routine in
      Button("删除", role: .destructive) {
        modelContext.delete(routine)
        try? modelContext.save()
        pendingDeletion = nil
      }
      Button("取消", role: .cancel) { pendingDeletion = nil }
    } message: { _ in
      Text("已经完成或正在进行的训练不会受到影响。")
    }
  }

  private var deletionAlertBinding: Binding<Bool> {
    Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
  }

  private func createRoutine() {
    let routine = Routine(name: "新 Routine")
    modelContext.insert(routine)
    presentation = RoutinePresentation(routine: routine, isNew: true)
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
  let isNew: Bool

  @State private var presentedSheet: RoutineEditorSheet?
  @State private var showCancelConfirmation = false

  private var canSave: Bool {
    !routine.name.trimmed.isEmpty && routine.exercises.allSatisfy(\.hasValidDefaults)
  }

  var body: some View {
    NavigationStack {
      List {
        Section("基本信息") {
          TextField("Routine 名称", text: $routine.name)
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
      .navigationTitle(isNew ? "新建 Routine" : "编辑 Routine")
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
      .sheet(item: $presentedSheet) { sheet in
        switch sheet {
        case .exercisePicker:
          ExercisePickerView(title: "添加 Routine 动作") { item in
            add(item)
          }
        }
      }
      .confirmationDialog(
        "放弃新 Routine？", isPresented: $showCancelConfirmation, titleVisibility: .visible
      ) {
        Button("放弃", role: .destructive) {
          modelContext.delete(routine)
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
    modelContext.delete(exercise)
    for (index, item) in routine.sortedExercises.filter({ $0.id != exercise.id }).enumerated() {
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
    try? modelContext.save()
    dismiss()
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

      LabeledContent("记录方式") {
        Label(exercise.trackingMode.title, systemImage: exercise.trackingMode.systemImage)
          .foregroundStyle(.secondary)
      }

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
      set: { exercise.defaultDurationSeconds = max(Int($0 * 60), 0) }
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
