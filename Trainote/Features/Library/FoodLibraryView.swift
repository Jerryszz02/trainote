import SwiftData
import SwiftUI

private enum FoodLibrarySection: String, CaseIterable, Identifiable {
  case presets = "常用食物"
  case meals = "固定餐"
  var id: Self { self }
  var title: String {
    switch self {
    case .presets: L10n.text("core.favorite.foods")
    case .meals: L10n.text("core.saved.meals")
    }
  }
}

private enum FoodLibraryPresentation: Identifiable {
  case preset(FoodPreset?)
  case meal(MealTemplate?)

  var id: String {
    switch self {
    case .preset(let preset): "preset-\(preset?.id.uuidString ?? "new")"
    case .meal(let template): "meal-\(template?.id.uuidString ?? "new")"
    }
  }
}

struct FoodLibraryView: View {
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \FoodPreset.name)
  private var presets: [FoodPreset]

  @Query(sort: \MealTemplate.name)
  private var templates: [MealTemplate]

  @State private var selectedSection: FoodLibrarySection = .presets
  @State private var presentation: FoodLibraryPresentation?
  @State private var pendingPresetDeletion: FoodPreset?
  @State private var pendingMealDeletion: MealTemplate?
  @State private var actionErrorMessage: L10n.Message?

  var body: some View {
    List {
      Section {
        Picker(L10n.text("core.food.library.category"), selection: $selectedSection) {
          ForEach(FoodLibrarySection.allCases) { Text($0.title).tag($0) }
        }
        .modifier(CoreAdaptivePickerStyle())
      }

      if selectedSection == .presets {
        presetsContent
      } else {
        templatesContent
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(L10n.text("core.new"), systemImage: "plus") {
          if selectedSection == .presets {
            presentation = .preset(nil)
          } else {
            presentation = .meal(nil)
          }
        }
        .accessibilityIdentifier("foodLibrary.create")
      }
    }
    .sheet(item: $presentation) { value in
      switch value {
      case .preset(let preset): FoodPresetEditor(preset: preset)
      case .meal(let template): MealTemplateEditor(template: template)
      }
    }
    .alert(L10n.text("core.delete.this.favorite.food"), isPresented: presetDeletionBinding, presenting: pendingPresetDeletion) {
      preset in
      Button(L10n.text("core.delete"), role: .destructive) {
        delete(preset)
      }
      Button(L10n.text("core.cancel"), role: .cancel) { pendingPresetDeletion = nil }
    } message: { _ in
      Text(L10n.text("core.existing.food.records.will.remain.unchanged"))
    }
    .alert(L10n.text("core.delete.this.saved.meal"), isPresented: mealDeletionBinding, presenting: pendingMealDeletion) {
      template in
      Button(L10n.text("core.delete"), role: .destructive) {
        delete(template)
      }
      Button(L10n.text("core.cancel"), role: .cancel) { pendingMealDeletion = nil }
    } message: { _ in
      Text(L10n.text("core.existing.food.records.will.remain.unchanged"))
    }
    .alert(L10n.text("core.action.failed"), isPresented: actionErrorBinding) {
      Button(L10n.text("core.ok.201"), role: .cancel) { actionErrorMessage = nil }
    } message: {
      Text(actionErrorMessage?.text ?? "")
    }
  }

  @ViewBuilder
  private var presetsContent: some View {
    Section(L10n.text("core.favorite.foods")) {
      if presets.isEmpty {
        ContentUnavailableView(L10n.text("core.no.favorite.foods.yet"), systemImage: "star")
      } else {
        ForEach(presets) { preset in
          Button {
            presentation = .preset(preset)
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
            Button(L10n.text("core.delete"), role: .destructive) { pendingPresetDeletion = preset }
          }
        }
      }
    }
  }

  @ViewBuilder
  private var templatesContent: some View {
    Section(L10n.text("core.saved.meals")) {
      if templates.isEmpty {
        ContentUnavailableView(L10n.text("core.no.saved.meals.yet"), systemImage: "list.bullet.rectangle")
      } else {
        ForEach(templates) { template in
          Button {
            presentation = .meal(template)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                Text(L10n.text("core.foods", template.items.count))
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
            Button(L10n.text("core.delete"), role: .destructive) { pendingMealDeletion = template }
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
      actionErrorMessage = L10n.Message(resolving: { L10n.text("core.delete.failed.please.try.again" , String(describing: error.localizedDescription)) })
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
      actionErrorMessage = L10n.Message(resolving: { L10n.text("core.delete.failed.please.try.again" , String(describing: error.localizedDescription)) })
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
  @State private var carbohydrates: Double
  @State private var protein: Double
  @State private var fat: Double
  @State private var macrosEdited = false
  @State private var errorMessage: L10n.Message?

  init(preset: FoodPreset?) {
    self.preset = preset
    _inputMode = State(
      initialValue: preset.map {
        FoodPortionMath.isPer100g($0.servingDescription) ? .per100g : .perServing
      }
        ?? .perServing)
    _name = State(initialValue: preset?.name ?? "")
    _servingDescription = State(initialValue: preset?.servingDescription ?? L10n.text("core.default.serving.description"))
    _carbohydrates = State(initialValue: preset?.carbohydratesPerServing ?? 0)
    _protein = State(initialValue: preset?.proteinPerServing ?? 0)
    _fat = State(initialValue: preset?.fatPerServing ?? 0)
  }

  private var calories: Double {
    if let preset, !macrosEdited {
      return preset.caloriesPerServing
    }
    return NutritionMath.calories(carbohydrates: carbohydrates, protein: protein, fat: fat)
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
        Section(L10n.text("core.food")) {
          TextField(L10n.text("core.name"), text: $name)
            .accessibilityIdentifier("foodPreset.name")
          Picker(L10n.text("core.nutrition.basis"), selection: $inputMode) {
            ForEach(PortionInputMode.allCases) { Text($0.title).tag($0) }
          }
          .modifier(CoreAdaptivePickerStyle())
          .accessibilityIdentifier("foodPreset.basis")
          if inputMode == .perServing {
            TextField(L10n.text("core.serving.description"), text: $servingDescription)
          } else {
            LabeledContent(L10n.text("core.serving.description")) {
              Text(FoodPortionMath.per100gServingDescription)
                .foregroundStyle(.secondary)
            }
          }
        }
        Section {
          LabeledContent(L10n.text("core.calories"), value: "\(NutritionFormatting.number(calories)) kcal")
            .accessibilityIdentifier("foodPreset.calories")
          field(L10n.text("core.carbs"), identifier: "碳水", value: $carbohydrates, unit: "g")
          field(L10n.text("core.protein"), identifier: "蛋白质", value: $protein, unit: "g")
          field(L10n.text("core.fat"), identifier: "脂肪", value: $fat, unit: "g")
        } header: {
          Text(inputMode.nutrientSectionTitle)
        } footer: {
          Text(NutritionMath.calorieCalculationNote)
        }
      }
      .navigationTitle(preset == nil ? L10n.text("core.new.favorite.food") : L10n.text("core.edit.favorite.food"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button(L10n.text("core.cancel")) { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("core.save"), action: save)
            .disabled(!isValid)
            .accessibilityIdentifier("foodPreset.save")
        }
        NutritionKeyboardDoneToolbar()
      }
      .alert(L10n.text("core.save.failed"), isPresented: errorBinding) {
        Button(L10n.text("core.ok.201"), role: .cancel) { errorMessage = nil }
      } message: {
        Text(errorMessage?.text ?? "")
      }
    }
  }

  private func field(_ title: String, identifier: String, value: Binding<Double>, unit: String) -> some View {
    LabeledContent(title) {
      HStack {
        StableNumberField(
          "0",
          value: Binding(
            get: { value.wrappedValue },
            set: {
              if $0 != value.wrappedValue { macrosEdited = true }
              value.wrappedValue = $0
            }
          ),
          format: .number.precision(.fractionLength(0...2)).locale(L10n.locale)
        )
          .accessibilityIdentifier("foodPreset.nutrient.\(identifier)")
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
      errorMessage = L10n.Message(resolving: { L10n.text("core.enter.a.name.and.serving.description.nutrition.values.must.be.finite.and.nonnegative") })
      return
    }
    let description = effectiveServingDescription
    let savedCalories = calories
    if let preset {
      let snapshot = (
        name: preset.name, serving: preset.servingDescription,
        calories: preset.caloriesPerServing, carbohydrates: preset.carbohydratesPerServing,
        protein: preset.proteinPerServing, fat: preset.fatPerServing, updatedAt: preset.updatedAt
      )
      preset.name = name.trimmed
      preset.servingDescription = description
      preset.caloriesPerServing = savedCalories
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
        errorMessage = L10n.Message(resolving: { L10n.text("core.save.failed.your.changes.are.still.in.the.form.please.try.again" , String(describing: error.localizedDescription)) })
      }
    } else {
      let preset = FoodPreset(
        name: name.trimmed,
        servingDescription: description,
        caloriesPerServing: savedCalories,
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
        errorMessage = L10n.Message(resolving: { L10n.text("core.save.failed.your.input.is.still.in.the.form.please.try.again" , String(describing: error.localizedDescription)) })
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
  @State private var errorMessage: L10n.Message?

  init(template: MealTemplate?) {
    self.template = template
    _draft = State(initialValue: MealTemplateDraft(template: template))
  }

  private var canSave: Bool { draft.isValid }

  var body: some View {
    NavigationStack {
      List {
        Section(L10n.text("core.saved.meals")) {
          TextField(L10n.text("core.name"), text: $draft.name)
            .accessibilityIdentifier("mealTemplate.name")
          TextField(L10n.text("core.notes.optional"), text: $draft.notes, axis: .vertical)
        }

        Section(L10n.text("core.food")) {
          ForEach($draft.items) { $item in
            MealTemplateItemDraftRow(item: $item) {
              draft.remove(id: item.id)
            }
          }
          Button(L10n.text("core.add.from.favorite.foods"), systemImage: "plus.circle.fill") {
            presentedSheet = .presetPicker
          }
          .accessibilityIdentifier("mealTemplate.addPreset")
        }
      }
      .navigationTitle(draft.isNew ? L10n.text("core.new.saved.meal") : L10n.text("core.edit.saved.meal"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(draft.isNew ? L10n.text("core.cancel") : L10n.text("core.close")) {
            if draft.isNew && !draft.isEmptyDraft {
              showCancelConfirmation = true
            } else {
              dismiss()
            }
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("core.save"), action: save)
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
        L10n.text("core.discard.this.new.saved.meal"), isPresented: $showCancelConfirmation, titleVisibility: .visible
      ) {
        Button(L10n.text("core.discard"), role: .destructive) { dismiss() }
        Button(L10n.text("core.keep.editing"), role: .cancel) {}
      } message: {
        Text(L10n.text("core.unsaved.changes.will.not.be.added.to.the.library"))
      }
      .alert(L10n.text("core.save.failed"), isPresented: errorBinding) {
        Button(L10n.text("core.ok.201"), role: .cancel) { errorMessage = nil }
      } message: {
        Text(errorMessage?.text ?? "")
      }
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func save() {
    guard canSave else {
      errorMessage = L10n.Message(resolving: { L10n.text("core.enter.a.meal.name.and.add.at.least.one.food.with.a.valid.quantity") })
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
        errorMessage = L10n.Message(resolving: { L10n.text("core.save.failed.your.changes.are.still.in.the.form.please.try.again" , String(describing: error.localizedDescription)) })
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
        errorMessage = L10n.Message(resolving: { L10n.text("core.save.failed.your.input.is.still.in.the.form.please.try.again" , String(describing: error.localizedDescription)) })
      }
    }
  }
}

private struct MealTemplateItemDraftRow: View {
  @ScaledMetric(relativeTo: .body) private var quantityWidth = 56.0
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
      StableNumberField(L10n.text("core.quantity"), value: displayQuantity, format: .number.precision(.fractionLength(0...2)).locale(L10n.locale))
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: quantityWidth)
      Text(FoodPortionMath.isPer100g(item.servingDescriptionSnapshot) ? "g" : L10n.text("core.servings"))
        .font(.caption).foregroundStyle(.secondary)
      Button(L10n.text("core.delete"), systemImage: "trash", role: .destructive, action: onDelete)
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
      .searchable(text: $searchText, prompt: L10n.text("core.search.favorite.foods"))
      .overlay {
        if presets.isEmpty {
          ContentUnavailableView(L10n.text("core.no.favorite.foods"), systemImage: "star")
        } else if filteredPresets.isEmpty {
          ContentUnavailableView(L10n.text("core.no.matching.favorite.foods"), systemImage: "magnifyingglass")
        }
      }
      .navigationTitle(L10n.text("core.choose.favorite.food"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button(L10n.text("core.cancel")) { dismiss() } }
      }
    }
  }
}
