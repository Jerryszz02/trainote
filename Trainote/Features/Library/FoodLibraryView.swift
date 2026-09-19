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
  let id = UUID()
  let template: MealTemplate?
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
  @State private var actionErrorMessage: String?

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
            mealPresentation = MealTemplatePresentation(template: nil)
          }
        }
        .accessibilityIdentifier("foodLibrary.create")
      }
    }
    .sheet(item: $presetPresentation) { value in
      FoodPresetEditor(preset: value.preset)
    }
    .sheet(item: $mealPresentation) { value in
      MealTemplateEditor(template: value.template)
    }
    .alert("删除常用食物？", isPresented: presetDeletionBinding, presenting: pendingPresetDeletion) {
      preset in
      Button("删除", role: .destructive) {
        delete(preset)
      }
      Button("取消", role: .cancel) { pendingPresetDeletion = nil }
    } message: { _ in
      Text("已经记录的饮食不会改变。")
    }
    .alert("删除固定餐？", isPresented: mealDeletionBinding, presenting: pendingMealDeletion) {
      template in
      Button("删除", role: .destructive) {
        delete(template)
      }
      Button("取消", role: .cancel) { pendingMealDeletion = nil }
    } message: { _ in
      Text("已经记录的饮食不会改变。")
    }
    .alert("操作失败", isPresented: actionErrorBinding) {
      Button("好", role: .cancel) { actionErrorMessage = nil }
    } message: {
      Text(actionErrorMessage ?? "")
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
                  "\(preset.servingDescription) · \(NutritionFormatting.number(preset.caloriesPerServing, fraction: 0)) kcal"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
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
            mealPresentation = MealTemplatePresentation(template: template)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
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

  private var actionErrorBinding: Binding<Bool> {
    Binding(get: { actionErrorMessage != nil }, set: { if !$0 { actionErrorMessage = nil } })
  }

  private func delete(_ preset: FoodPreset) {
    modelContext.delete(preset)
    do {
      try modelContext.save()
      pendingPresetDeletion = nil
    } catch {
      modelContext.rollback()
      pendingPresetDeletion = nil
      actionErrorMessage = "删除失败：\(error.localizedDescription)。请重试。"
    }
  }

  private func delete(_ template: MealTemplate) {
    modelContext.delete(template)
    do {
      try modelContext.save()
      pendingMealDeletion = nil
    } catch {
      modelContext.rollback()
      pendingMealDeletion = nil
      actionErrorMessage = "删除失败：\(error.localizedDescription)。请重试。"
    }
  }
}

private struct FoodPresetEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  let preset: FoodPreset?
  @State private var inputMode: PortionInputMode
  @State private var name: String
  @State private var servingDescription: String
  @State private var calories: Double
  @State private var carbohydrates: Double
  @State private var protein: Double
  @State private var fat: Double
  @State private var errorMessage: String?

  init(preset: FoodPreset?) {
    self.preset = preset
    _inputMode = State(
      initialValue: preset.map {
        FoodPortionMath.isPer100g($0.servingDescription) ? .per100g : .perServing
      }
        ?? .perServing)
    _name = State(initialValue: preset?.name ?? "")
    _servingDescription = State(initialValue: preset?.servingDescription ?? "1 份")
    _calories = State(initialValue: preset?.caloriesPerServing ?? 0)
    _carbohydrates = State(initialValue: preset?.carbohydratesPerServing ?? 0)
    _protein = State(initialValue: preset?.proteinPerServing ?? 0)
    _fat = State(initialValue: preset?.fatPerServing ?? 0)
  }

  private var effectiveServingDescription: String {
    inputMode == .per100g ? FoodPortionMath.per100gServingDescription : servingDescription.trimmed
  }

  private var isValid: Bool {
    !name.trimmed.isEmpty
      && !effectiveServingDescription.isEmpty
      && [calories, carbohydrates, protein, fat].allSatisfy(\.isValidNonnegativeNumber)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("食物") {
          TextField("名称", text: $name)
            .accessibilityIdentifier("foodPreset.name")
          Picker("营养基准", selection: $inputMode) {
            ForEach(PortionInputMode.allCases) { Text($0.title).tag($0) }
          }
          .accessibilityIdentifier("foodPreset.basis")
          if inputMode == .perServing {
            TextField("每份说明", text: $servingDescription)
          } else {
            LabeledContent("每份说明") {
              Text(FoodPortionMath.per100gServingDescription)
                .foregroundStyle(.secondary)
            }
          }
        }
        Section(inputMode.nutrientSectionTitle) {
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
        NutritionKeyboardDoneToolbar()
      }
      .alert("保存失败", isPresented: errorBinding) {
        Button("好", role: .cancel) { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
    }
  }

  private func field(_ title: String, value: Binding<Double>, unit: String) -> some View {
    LabeledContent(title) {
      HStack {
        TextField("0", value: value, format: .number.precision(.fractionLength(0...2)))
          .accessibilityIdentifier("foodPreset.nutrient.\(title)")
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
        Text(unit).foregroundStyle(.secondary)
      }
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func save() {
    guard isValid else {
      errorMessage = "请填写名称和份量说明，营养数值必须为有限非负数。"
      return
    }
    let description = effectiveServingDescription
    if let preset {
      let snapshot = (
        name: preset.name, serving: preset.servingDescription,
        calories: preset.caloriesPerServing, carbohydrates: preset.carbohydratesPerServing,
        protein: preset.proteinPerServing, fat: preset.fatPerServing, updatedAt: preset.updatedAt
      )
      preset.name = name.trimmed
      preset.servingDescription = description
      preset.caloriesPerServing = calories
      preset.carbohydratesPerServing = carbohydrates
      preset.proteinPerServing = protein
      preset.fatPerServing = fat
      preset.updatedAt = .now
      do {
        try modelContext.save()
        dismiss()
      } catch {
        preset.name = snapshot.name
        preset.servingDescription = snapshot.serving
        preset.caloriesPerServing = snapshot.calories
        preset.carbohydratesPerServing = snapshot.carbohydrates
        preset.proteinPerServing = snapshot.protein
        preset.fatPerServing = snapshot.fat
        preset.updatedAt = snapshot.updatedAt
        errorMessage = "保存失败：\(error.localizedDescription)。修改仍保留在表单中，请重试。"
      }
    } else {
      let preset = FoodPreset(
        name: name.trimmed,
        servingDescription: description,
        caloriesPerServing: calories,
        carbohydratesPerServing: carbohydrates,
        proteinPerServing: protein,
        fatPerServing: fat
      )
      modelContext.insert(preset)
      do {
        try modelContext.save()
        dismiss()
      } catch {
        modelContext.delete(preset)
        errorMessage = "保存失败：\(error.localizedDescription)。输入仍保留在表单中，请重试。"
      }
    }
  }
}

private enum MealEditorSheet: String, Identifiable {
  case presetPicker
  var id: String { rawValue }
}

/// 固定餐编辑用的纯值草稿，只有显式保存才会写入 SwiftData。
struct MealTemplateItemDraft: Identifiable, Equatable {
  let id: UUID
  var orderIndex: Int
  var nameSnapshot: String
  var servingDescriptionSnapshot: String
  var quantity: Double
  var caloriesPerServing: Double
  var carbohydratesPerServing: Double
  var proteinPerServing: Double
  var fatPerServing: Double

  var isValid: Bool {
    !nameSnapshot.trimmed.isEmpty
      && !servingDescriptionSnapshot.trimmed.isEmpty
      && quantity.isFinite && quantity > 0
      && caloriesPerServing.isValidNonnegativeNumber
      && carbohydratesPerServing.isValidNonnegativeNumber
      && proteinPerServing.isValidNonnegativeNumber
      && fatPerServing.isValidNonnegativeNumber
      && (caloriesPerServing * quantity).isValidNonnegativeNumber
      && (carbohydratesPerServing * quantity).isValidNonnegativeNumber
      && (proteinPerServing * quantity).isValidNonnegativeNumber
      && (fatPerServing * quantity).isValidNonnegativeNumber
  }
}

struct MealTemplateDraft: Identifiable, Equatable {
  let id: UUID
  let isNew: Bool
  var name: String
  var notes: String
  var items: [MealTemplateItemDraft]

  init(template: MealTemplate?) {
    if let template {
      id = template.id
      isNew = false
      name = template.name
      notes = template.notes
      items = template.sortedItems.map { item in
        MealTemplateItemDraft(
          id: item.id,
          orderIndex: item.orderIndex,
          nameSnapshot: item.nameSnapshot,
          servingDescriptionSnapshot: item.servingDescriptionSnapshot,
          quantity: item.quantity,
          caloriesPerServing: item.caloriesPerServing,
          carbohydratesPerServing: item.carbohydratesPerServing,
          proteinPerServing: item.proteinPerServing,
          fatPerServing: item.fatPerServing
        )
      }
    } else {
      id = UUID()
      isNew = true
      name = ""
      notes = ""
      items = []
    }
  }

  var isValid: Bool {
    !name.trimmed.isEmpty && !items.isEmpty && items.allSatisfy(\.isValid)
  }

  var isEmptyDraft: Bool {
    name.trimmed.isEmpty && notes.trimmed.isEmpty && items.isEmpty
  }

  mutating func add(preset: FoodPreset) {
    items.append(
      MealTemplateItemDraft(
        id: UUID(),
        orderIndex: items.count,
        nameSnapshot: preset.name,
        servingDescriptionSnapshot: preset.servingDescription,
        quantity: 1,
        caloriesPerServing: preset.caloriesPerServing,
        carbohydratesPerServing: preset.carbohydratesPerServing,
        proteinPerServing: preset.proteinPerServing,
        fatPerServing: preset.fatPerServing
      )
    )
  }

  mutating func remove(id: UUID) {
    items.removeAll { $0.id == id }
    for index in items.indices { items[index].orderIndex = index }
  }
}

private struct MealTemplateEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  let template: MealTemplate?
  @State private var draft: MealTemplateDraft
  @State private var presentedSheet: MealEditorSheet?
  @State private var showCancelConfirmation = false
  @State private var errorMessage: String?

  init(template: MealTemplate?) {
    self.template = template
    _draft = State(initialValue: MealTemplateDraft(template: template))
  }

  private var canSave: Bool { draft.isValid }

  var body: some View {
    NavigationStack {
      List {
        Section("固定餐") {
          TextField("名称", text: $draft.name)
            .accessibilityIdentifier("mealTemplate.name")
          TextField("备注（可选）", text: $draft.notes, axis: .vertical)
        }

        Section("食物") {
          ForEach($draft.items) { $item in
            MealTemplateItemDraftRow(item: $item) {
              draft.remove(id: item.id)
            }
          }
          Button("从常用食物添加", systemImage: "plus.circle.fill") {
            presentedSheet = .presetPicker
          }
          .accessibilityIdentifier("mealTemplate.addPreset")
        }
      }
      .navigationTitle(draft.isNew ? "新建固定餐" : "编辑固定餐")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(draft.isNew ? "取消" : "关闭") {
            if draft.isNew && !draft.isEmptyDraft {
              showCancelConfirmation = true
            } else {
              dismiss()
            }
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存", action: save)
            .disabled(!canSave)
            .accessibilityIdentifier("mealTemplate.save")
        }
        NutritionKeyboardDoneToolbar()
      }
      .sheet(item: $presentedSheet) { _ in
        MealTemplatePresetPicker { preset in
          draft.add(preset: preset)
        }
      }
      .confirmationDialog(
        "放弃新固定餐？", isPresented: $showCancelConfirmation, titleVisibility: .visible
      ) {
        Button("放弃", role: .destructive) { dismiss() }
        Button("继续编辑", role: .cancel) {}
      } message: {
        Text("尚未保存的修改不会保留到资料库。")
      }
      .alert("保存失败", isPresented: errorBinding) {
        Button("好", role: .cancel) { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func save() {
    guard canSave else {
      errorMessage = "请填写固定餐名称，并至少添加一项数量有效的食物。"
      return
    }
    if let template {
      let previousName = template.name
      let previousNotes = template.notes
      let previousUpdatedAt = template.updatedAt
      let draftIDs = Set(draft.items.map(\.id))
      var existingByID: [UUID: MealTemplateItem] = [:]
      for item in template.items {
        existingByID[item.id] = item
        if !draftIDs.contains(item.id) {
          modelContext.delete(item)
        }
      }
      for (index, itemDraft) in draft.items.enumerated() {
        if let item = existingByID[itemDraft.id] {
          item.orderIndex = index
          item.nameSnapshot = itemDraft.nameSnapshot
          item.servingDescriptionSnapshot = itemDraft.servingDescriptionSnapshot
          item.quantity = itemDraft.quantity
          item.caloriesPerServing = itemDraft.caloriesPerServing
          item.carbohydratesPerServing = itemDraft.carbohydratesPerServing
          item.proteinPerServing = itemDraft.proteinPerServing
          item.fatPerServing = itemDraft.fatPerServing
        } else {
          let item = MealTemplateItem(
            id: itemDraft.id,
            orderIndex: index,
            nameSnapshot: itemDraft.nameSnapshot,
            servingDescriptionSnapshot: itemDraft.servingDescriptionSnapshot,
            quantity: itemDraft.quantity,
            caloriesPerServing: itemDraft.caloriesPerServing,
            carbohydratesPerServing: itemDraft.carbohydratesPerServing,
            proteinPerServing: itemDraft.proteinPerServing,
            fatPerServing: itemDraft.fatPerServing
          )
          item.template = template
          template.items.append(item)
        }
      }
      template.name = draft.name.trimmed
      template.notes = draft.notes
      template.updatedAt = .now
      do {
        try modelContext.save()
        dismiss()
      } catch {
        template.name = previousName
        template.notes = previousNotes
        template.updatedAt = previousUpdatedAt
        modelContext.rollback()
        errorMessage = "保存失败：\(error.localizedDescription)。修改仍保留在表单中，请重试。"
      }
    } else {
      let template = MealTemplate(id: draft.id, name: draft.name.trimmed, notes: draft.notes)
      template.items = draft.items.enumerated().map { index, itemDraft in
        let item = MealTemplateItem(
          id: itemDraft.id,
          orderIndex: index,
          nameSnapshot: itemDraft.nameSnapshot,
          servingDescriptionSnapshot: itemDraft.servingDescriptionSnapshot,
          quantity: itemDraft.quantity,
          caloriesPerServing: itemDraft.caloriesPerServing,
          carbohydratesPerServing: itemDraft.carbohydratesPerServing,
          proteinPerServing: itemDraft.proteinPerServing,
          fatPerServing: itemDraft.fatPerServing
        )
        item.template = template
        return item
      }
      modelContext.insert(template)
      do {
        try modelContext.save()
        dismiss()
      } catch {
        modelContext.rollback()
        errorMessage = "保存失败：\(error.localizedDescription)。输入仍保留在表单中，请重试。"
      }
    }
  }
}

private struct MealTemplateItemDraftRow: View {
  @Binding var item: MealTemplateItemDraft
  let onDelete: () -> Void

  private var displayQuantity: Binding<Double> {
    let factor = FoodPortionMath.isPer100g(item.servingDescriptionSnapshot) ? 100.0 : 1.0
    return Binding(get: { item.quantity * factor }, set: { item.quantity = $0 / factor })
  }

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        Text(item.nameSnapshot)
        Text(item.servingDescriptionSnapshot)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      TextField("数量", value: displayQuantity, format: .number.precision(.fractionLength(0...2)))
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 56)
      Text(FoodPortionMath.isPer100g(item.servingDescriptionSnapshot) ? "g" : "份")
        .font(.caption).foregroundStyle(.secondary)
      Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
        .labelStyle(.iconOnly)
    }
  }
}

private struct MealTemplatePresetPicker: View {
  @Environment(\.dismiss) private var dismiss

  @Query(sort: \FoodPreset.name)
  private var presets: [FoodPreset]

  let onSelect: (FoodPreset) -> Void

  @State private var searchText = ""

  private var filteredPresets: [FoodPreset] {
    let normalized = searchText.trimmed.lowercased()
    guard !normalized.isEmpty else { return presets }
    return presets.filter {
      $0.name.lowercased().contains(normalized)
        || $0.servingDescription.lowercased().contains(normalized)
    }
  }

  var body: some View {
    NavigationStack {
      List(filteredPresets) { preset in
        Button {
          onSelect(preset)
          dismiss()
        } label: {
          VStack(alignment: .leading, spacing: 3) {
            Text(preset.name)
            Text(
              "\(preset.servingDescription) · \(NutritionFormatting.number(preset.caloriesPerServing, fraction: 0)) kcal"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .searchable(text: $searchText, prompt: "搜索常用食物")
      .overlay {
        if presets.isEmpty {
          ContentUnavailableView("没有常用食物", systemImage: "star")
        } else if filteredPresets.isEmpty {
          ContentUnavailableView("没有匹配的常用食物", systemImage: "magnifyingglass")
        }
      }
      .navigationTitle("选择常用食物")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
      }
    }
  }
}
