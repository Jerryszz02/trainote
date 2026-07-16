import SwiftData
import SwiftUI

private enum FoodLibrarySection: String, CaseIterable, Identifiable {
  case presets = "常用食物"
  case meals = "固定餐"
  var id: Self { self }
}

private struct FoodPresetPresentation: Identifiable {
  let id = UUID()
  let preset: FoodPreset?
}

private struct MealTemplatePresentation: Identifiable {
  let template: MealTemplate
  let isNew: Bool
  var id: UUID { template.id }
}

struct FoodLibraryView: View {
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \FoodPreset.name)
  private var presets: [FoodPreset]

  @Query(sort: \MealTemplate.name)
  private var templates: [MealTemplate]

  @State private var selectedSection: FoodLibrarySection = .presets
  @State private var presetPresentation: FoodPresetPresentation?
  @State private var mealPresentation: MealTemplatePresentation?
  @State private var pendingPresetDeletion: FoodPreset?
  @State private var pendingMealDeletion: MealTemplate?

  var body: some View {
    List {
      Section {
        Picker("饮食资料类型", selection: $selectedSection) {
          ForEach(FoodLibrarySection.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
      }

      if selectedSection == .presets {
        presetsContent
      } else {
        templatesContent
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("新建", systemImage: "plus") {
          if selectedSection == .presets {
            presetPresentation = FoodPresetPresentation(preset: nil)
          } else {
            createMealTemplate()
          }
        }
        .accessibilityIdentifier("foodLibrary.create")
      }
    }
    .sheet(item: $presetPresentation) { value in
      FoodPresetEditor(preset: value.preset)
    }
    .sheet(item: $mealPresentation) { value in
      MealTemplateEditor(template: value.template, isNew: value.isNew)
    }
    .alert("删除常用食物？", isPresented: presetDeletionBinding, presenting: pendingPresetDeletion) {
      preset in
      Button("删除", role: .destructive) {
        modelContext.delete(preset)
        try? modelContext.save()
        pendingPresetDeletion = nil
      }
      Button("取消", role: .cancel) { pendingPresetDeletion = nil }
    } message: { _ in
      Text("已经记录的饮食不会改变。")
    }
    .alert("删除固定餐？", isPresented: mealDeletionBinding, presenting: pendingMealDeletion) {
      template in
      Button("删除", role: .destructive) {
        modelContext.delete(template)
        try? modelContext.save()
        pendingMealDeletion = nil
      }
      Button("取消", role: .cancel) { pendingMealDeletion = nil }
    } message: { _ in
      Text("已经记录的饮食不会改变。")
    }
  }

  @ViewBuilder
  private var presetsContent: some View {
    Section("常用食物") {
      if presets.isEmpty {
        ContentUnavailableView("还没有常用食物", systemImage: "star")
      } else {
        ForEach(presets) { preset in
          Button {
            presetPresentation = FoodPresetPresentation(preset: preset)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text(preset.name)
                Text(
                  "\(preset.servingDescription) · \(preset.caloriesPerServing, format: .number.precision(.fractionLength(0))) kcal"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
          }
          .buttonStyle(.plain)
          .swipeActions {
            Button("删除", role: .destructive) { pendingPresetDeletion = preset }
          }
        }
      }
    }
  }

  @ViewBuilder
  private var templatesContent: some View {
    Section("固定餐") {
      if templates.isEmpty {
        ContentUnavailableView("还没有固定餐", systemImage: "list.bullet.rectangle")
      } else {
        ForEach(templates) { template in
          Button {
            mealPresentation = MealTemplatePresentation(template: template, isNew: false)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                Text("\(template.items.count) 项食物")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
          }
          .buttonStyle(.plain)
          .swipeActions {
            Button("删除", role: .destructive) { pendingMealDeletion = template }
          }
        }
      }
    }
  }

  private var presetDeletionBinding: Binding<Bool> {
    Binding(get: { pendingPresetDeletion != nil }, set: { if !$0 { pendingPresetDeletion = nil } })
  }

  private var mealDeletionBinding: Binding<Bool> {
    Binding(get: { pendingMealDeletion != nil }, set: { if !$0 { pendingMealDeletion = nil } })
  }

  private func createMealTemplate() {
    let template = MealTemplate(name: "新固定餐")
    modelContext.insert(template)
    mealPresentation = MealTemplatePresentation(template: template, isNew: true)
  }
}

private struct FoodPresetEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  let preset: FoodPreset?
  @State private var name: String
  @State private var servingDescription: String
  @State private var calories: Double
  @State private var carbohydrates: Double
  @State private var protein: Double
  @State private var fat: Double

  init(preset: FoodPreset?) {
    self.preset = preset
    _name = State(initialValue: preset?.name ?? "")
    _servingDescription = State(initialValue: preset?.servingDescription ?? "1 份")
    _calories = State(initialValue: preset?.caloriesPerServing ?? 0)
    _carbohydrates = State(initialValue: preset?.carbohydratesPerServing ?? 0)
    _protein = State(initialValue: preset?.proteinPerServing ?? 0)
    _fat = State(initialValue: preset?.fatPerServing ?? 0)
  }

  private var isValid: Bool {
    !name.trimmed.isEmpty
      && !servingDescription.trimmed.isEmpty
      && [calories, carbohydrates, protein, fat].allSatisfy(\.isValidNonnegativeNumber)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("食物") {
          TextField("名称", text: $name)
            .accessibilityIdentifier("foodPreset.name")
          TextField("每份说明", text: $servingDescription)
        }
        Section("每份营养") {
          field("卡路里", value: $calories, unit: "kcal")
          field("碳水", value: $carbohydrates, unit: "g")
          field("蛋白质", value: $protein, unit: "g")
          field("脂肪", value: $fat, unit: "g")
        }
      }
      .navigationTitle(preset == nil ? "新建常用食物" : "编辑常用食物")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存", action: save)
            .disabled(!isValid)
            .accessibilityIdentifier("foodPreset.save")
        }
      }
    }
  }

  private func field(_ title: String, value: Binding<Double>, unit: String) -> some View {
    LabeledContent(title) {
      HStack {
        TextField("0", value: value, format: .number.precision(.fractionLength(0...2)))
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
        Text(unit).foregroundStyle(.secondary)
      }
    }
  }

  private func save() {
    guard isValid else { return }
    if let preset {
      preset.name = name.trimmed
      preset.servingDescription = servingDescription.trimmed
      preset.caloriesPerServing = calories
      preset.carbohydratesPerServing = carbohydrates
      preset.proteinPerServing = protein
      preset.fatPerServing = fat
      preset.updatedAt = .now
    } else {
      modelContext.insert(
        FoodPreset(
          name: name.trimmed,
          servingDescription: servingDescription.trimmed,
          caloriesPerServing: calories,
          carbohydratesPerServing: carbohydrates,
          proteinPerServing: protein,
          fatPerServing: fat
        )
      )
    }
    try? modelContext.save()
    dismiss()
  }
}

private enum MealEditorSheet: String, Identifiable {
  case presetPicker
  var id: String { rawValue }
}

private struct MealTemplateEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @Bindable var template: MealTemplate
  let isNew: Bool

  @State private var presentedSheet: MealEditorSheet?
  @State private var showCancelConfirmation = false

  private var canSave: Bool { template.isValid }

  var body: some View {
    NavigationStack {
      List {
        Section("固定餐") {
          TextField("名称", text: $template.name)
          TextField("备注（可选）", text: $template.notes, axis: .vertical)
        }

        Section("食物") {
          ForEach(template.sortedItems) { item in
            MealTemplateItemRow(item: item) { delete(item) }
          }
          Button("从常用食物添加", systemImage: "plus.circle.fill") {
            presentedSheet = .presetPicker
          }
        }
      }
      .navigationTitle(isNew ? "新建固定餐" : "编辑固定餐")
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
            .accessibilityIdentifier("mealTemplate.save")
        }
      }
      .sheet(item: $presentedSheet) { _ in
        MealTemplatePresetPicker(template: template)
      }
      .confirmationDialog(
        "放弃新固定餐？", isPresented: $showCancelConfirmation, titleVisibility: .visible
      ) {
        Button("放弃", role: .destructive) {
          modelContext.delete(template)
          dismiss()
        }
        Button("继续编辑", role: .cancel) {}
      }
    }
  }

  private func delete(_ item: MealTemplateItem) {
    modelContext.delete(item)
    for (index, value) in template.sortedItems.filter({ $0.id != item.id }).enumerated() {
      value.orderIndex = index
    }
    template.updatedAt = .now
  }

  private func save() {
    guard canSave else { return }
    template.name = template.name.trimmed
    template.updatedAt = .now
    try? modelContext.save()
    dismiss()
  }
}

private struct MealTemplateItemRow: View {
  @Bindable var item: MealTemplateItem
  let onDelete: () -> Void

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        Text(item.nameSnapshot)
        Text(item.servingDescriptionSnapshot)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      TextField("数量", value: $item.quantity, format: .number.precision(.fractionLength(0...2)))
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 56)
      Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
        .labelStyle(.iconOnly)
    }
  }
}

private struct MealTemplatePresetPicker: View {
  @Environment(\.dismiss) private var dismiss

  @Query(sort: \FoodPreset.name)
  private var presets: [FoodPreset]

  let template: MealTemplate

  var body: some View {
    NavigationStack {
      List(presets) { preset in
        Button {
          add(preset)
          dismiss()
        } label: {
          VStack(alignment: .leading, spacing: 3) {
            Text(preset.name)
            Text(
              "\(preset.servingDescription) · \(preset.caloriesPerServing, format: .number.precision(.fractionLength(0))) kcal"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.plain)
      }
      .overlay {
        if presets.isEmpty {
          ContentUnavailableView("没有常用食物", systemImage: "star")
        }
      }
      .navigationTitle("选择常用食物")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
      }
    }
  }

  private func add(_ preset: FoodPreset) {
    let item = MealTemplateItem(
      orderIndex: template.items.count,
      nameSnapshot: preset.name,
      servingDescriptionSnapshot: preset.servingDescription,
      quantity: 1,
      caloriesPerServing: preset.caloriesPerServing,
      carbohydratesPerServing: preset.carbohydratesPerServing,
      proteinPerServing: preset.proteinPerServing,
      fatPerServing: preset.fatPerServing
    )
    item.template = template
    template.items.append(item)
    template.updatedAt = .now
  }
}
