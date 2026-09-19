import SwiftData
import SwiftUI
import UIKit

private enum NutritionSheet: Identifiable {
  case addOptions
  case entry(FoodLogEntry?)
  case recentPicker
  case presetPicker
  case mealPicker
  case copyPicker

  var id: String {
    switch self {
    case .addOptions: "add-options"
    case .entry(let entry): "entry-\(entry?.id.uuidString ?? "new")"
    case .recentPicker: "recent-picker"
    case .presetPicker: "preset-picker"
    case .mealPicker: "meal-picker"
    case .copyPicker: "copy-picker"
    }
  }
}

/// 数字键盘上的“完成”按钮，Nutrition 与资料库表单共用。
struct NutritionKeyboardDoneToolbar: ToolbarContent {
  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .keyboard) {
      Spacer()
      Button("完成") {
        UIApplication.shared.sendAction(
          #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      }
    }
  }
}

struct NutritionView: View {
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \FoodLogEntry.loggedAt, order: .reverse)
  private var entries: [FoodLogEntry]

  @State private var selectedDate = Date.now
  @State private var presentedSheet: NutritionSheet?
  @State private var pendingDeletion: FoodLogEntry?
  @State private var actionErrorMessage: String?

  let addRequest: Int

  private var dayEntries: [FoodLogEntry] {
    entries.filter { Calendar.current.isDate($0.loggedAt, inSameDayAs: selectedDate) }
  }

  private var dayTotals: NutritionValues {
    NutritionMath.totals(of: dayEntries)
  }

  var body: some View {
    List {
      Section {
        DatePicker(
          "记录日期",
          selection: $selectedDate,
          displayedComponents: .date
        )
        .datePickerStyle(.compact)
      }

      daySummarySection

      ForEach(MealType.allCases) { mealType in
        mealSection(mealType)
      }

      if dayEntries.isEmpty {
        ContentUnavailableView(
          "当天没有饮食记录",
          systemImage: "fork.knife.circle",
          description: Text("点击右上角加号，可选择直接记录、最近记录、常用食物、固定餐或复制某一餐。")
        )
        .frame(maxWidth: .infinity)
      }
    }
    .navigationTitle("饮食")
    .onChange(of: addRequest, initial: true) { _, newValue in
      if newValue > 0 {
        selectedDate = .now
        presentedSheet = .addOptions
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          presentedSheet = .addOptions
        } label: {
          Label("添加饮食", systemImage: "plus")
        }
        .accessibilityIdentifier("nutrition.add")
        .accessibilityLabel("添加饮食")
      }
    }
    .sheet(
      isPresented: Binding(
        get: { presentedSheet != nil },
        set: { if !$0 { presentedSheet = nil } }
      )
    ) {
      if let sheet = presentedSheet {
        switch sheet {
        case .addOptions:
          AddFoodOptionsSheet { presentedSheet = $0 }
        case .entry(let entry):
          FoodEntryEditor(date: selectedDate, entry: entry)
        case .recentPicker:
          RecentFoodPickerSheet(selectedDate: selectedDate)
        case .presetPicker:
          FoodPresetLogSheet(selectedDate: selectedDate)
        case .mealPicker:
          MealTemplateLogSheet(selectedDate: selectedDate)
        case .copyPicker:
          CopyMealSheet(selectedDate: selectedDate)
        }
      }
    }
    .alert("删除这条饮食记录？", isPresented: deletionAlertBinding, presenting: pendingDeletion) { entry in
      Button("删除", role: .destructive) {
        delete(entry)
      }
      Button("取消", role: .cancel) { pendingDeletion = nil }
    } message: { _ in
      Text("当天营养汇总会立即更新。")
    }
    .alert("操作失败", isPresented: actionErrorBinding) {
      Button("好", role: .cancel) { actionErrorMessage = nil }
    } message: {
      Text(actionErrorMessage ?? "")
    }
  }

  private var daySummarySection: some View {
    Section("当日营养") {
      summaryRow("卡路里", value: dayTotals.calories, unit: "kcal")
      summaryRow("碳水", value: dayTotals.carbohydrates, unit: "g")
      summaryRow("蛋白质", value: dayTotals.protein, unit: "g")
      summaryRow("脂肪", value: dayTotals.fat, unit: "g")
      if !dayEntries.isEmpty && dayTotals.isAllZero {
        Text("当天记录都未填写营养")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func summaryRow(_ title: String, value: Double, unit: String) -> some View {
    LabeledContent(title) {
      Text("\(NutritionFormatting.number(value)) \(unit)")
        .monospacedDigit()
        .foregroundStyle(value == 0 ? .secondary : .primary)
    }
  }

  @ViewBuilder
  private func mealSection(_ mealType: MealType) -> some View {
    let mealEntries = dayEntries.filter { $0.mealType == mealType }
    if !mealEntries.isEmpty {
      let totals = NutritionMath.totals(of: mealEntries)
      Section {
        ForEach(mealEntries) { entry in
          Button {
            presentedSheet = .entry(entry)
          } label: {
            FoodLogRow(entry: entry)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .swipeActions {
            Button("删除", role: .destructive) { pendingDeletion = entry }
          }
        }
      } header: {
        HStack {
          Label(mealType.title, systemImage: mealType.systemImage)
          Spacer()
          if totals.isAllZero {
            Text("未填写营养")
          } else {
            Text("\(NutritionFormatting.number(totals.calories, fraction: 0)) kcal")
              .monospacedDigit()
          }
        }
      }
    }
  }

  private var deletionAlertBinding: Binding<Bool> {
    Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
  }

  private var actionErrorBinding: Binding<Bool> {
    Binding(get: { actionErrorMessage != nil }, set: { if !$0 { actionErrorMessage = nil } })
  }

  private func delete(_ entry: FoodLogEntry) {
    modelContext.delete(entry)
    do {
      try modelContext.save()
      pendingDeletion = nil
    } catch {
      modelContext.rollback()
      pendingDeletion = nil
      actionErrorMessage = "删除失败：\(error.localizedDescription)。请重试。"
    }
  }
}

private struct AddFoodOptionsSheet: View {
  @Environment(\.dismiss) private var dismiss

  let onSelect: (NutritionSheet) -> Void

  var body: some View {
    NavigationStack {
      List {
        Section {
          optionButton(
            "直接记录", systemImage: "square.and.pencil",
            detail: "手动填写食物和营养", accessibilityIdentifier: "nutrition.add.direct"
          ) { onSelect(.entry(nil)) }
          optionButton(
            "最近记录", systemImage: "clock.arrow.circlepath",
            detail: "从吃过的食物里选，可改份量", accessibilityIdentifier: "nutrition.add.recent"
          ) { onSelect(.recentPicker) }
          optionButton(
            "常用食物", systemImage: "star.fill",
            detail: "从常用食物快速记录", accessibilityIdentifier: "nutrition.add.preset"
          ) { onSelect(.presetPicker) }
          optionButton(
            "固定餐", systemImage: "list.bullet.rectangle",
            detail: "整套记录，逐项调整份量", accessibilityIdentifier: "nutrition.add.meal"
          ) { onSelect(.mealPicker) }
          optionButton(
            "复制某一餐", systemImage: "doc.on.doc",
            detail: "把某天某餐整体复制过来", accessibilityIdentifier: "nutrition.add.copy"
          ) { onSelect(.copyPicker) }
        } footer: {
          Text("所有方式都会在保存前显示营养总量预览。")
        }
      }
      .navigationTitle("添加饮食")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
            .accessibilityIdentifier("nutrition.add.cancel")
        }
      }
    }
  }

  private func optionButton(
    _ title: String,
    systemImage: String,
    detail: String,
    accessibilityIdentifier: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: systemImage)
          .foregroundStyle(.tint)
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(accessibilityIdentifier)
  }
}

private struct FoodLogRow: View {
  let entry: FoodLogEntry

  private var nutrition: NutritionValues {
    NutritionValues(
      calories: entry.calories,
      carbohydrates: entry.carbohydrates,
      protein: entry.protein,
      fat: entry.fat
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(entry.name).font(.body.weight(.medium))
        Spacer()
        Text("\(NutritionFormatting.number(entry.calories, fraction: 0)) kcal")
          .font(.subheadline.monospacedDigit())
      }
      Text(
        "\(NutritionFormatting.number(entry.quantity, fraction: 2)) × \(entry.servingDescription)"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      if nutrition.isAllZero {
        Text("未填写营养")
          .font(.caption2)
          .foregroundStyle(.orange)
      } else {
        Text(
          "碳水 \(NutritionFormatting.number(entry.carbohydrates))g · 蛋白质 \(NutritionFormatting.number(entry.protein))g · 脂肪 \(NutritionFormatting.number(entry.fat))g"
        )
        .font(.caption2)
        .foregroundStyle(.tertiary)
      }
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

private struct FoodEntryEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  let entry: FoodLogEntry?

  @State private var draft: FoodNutritionDraft
  @State private var mealType: MealType
  @State private var loggedAt: Date
  @State private var saveAsPreset = false
  @State private var errorMessage: String?

  init(date: Date, entry: FoodLogEntry?) {
    self.entry = entry
    if let entry {
      _draft = State(initialValue: .fromEntry(entry))
      _mealType = State(initialValue: entry.mealType)
      _loggedAt = State(initialValue: entry.loggedAt)
    } else {
      _draft = State(initialValue: FoodNutritionDraft())
      _mealType = State(initialValue: MealType.defaultForTime())
      _loggedAt = State(initialValue: date.withCurrentTime())
    }
  }

  private var isValid: Bool { draft.isValid }

  var body: some View {
    NavigationStack {
      Form {
        Section("食物") {
          TextField("名称", text: $draft.name)
            .accessibilityIdentifier("nutrition.entry.name")
          Picker(
            "营养基准",
            selection: Binding(get: { draft.inputMode }, set: { draft.changeInputMode(to: $0) })
          ) {
            ForEach(PortionInputMode.allCases) { Text($0.title).tag($0) }
          }
          .accessibilityIdentifier("nutrition.entry.basis")
          if draft.inputMode == .perServing {
            TextField("份量说明", text: $draft.servingDescription)
              .accessibilityIdentifier("nutrition.entry.serving")
          } else {
            LabeledContent("份量说明") {
              Text(FoodPortionMath.per100gServingDescription)
                .foregroundStyle(.secondary)
            }
          }
          LabeledContent(draft.inputMode.amountTitle) {
            TextField("1", value: $draft.amount, format: .number.precision(.fractionLength(0...2)))
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
              .accessibilityIdentifier("nutrition.entry.amount")
          }
          Picker("餐次", selection: $mealType) {
            ForEach(MealType.allCases) { Text($0.title).tag($0) }
          }
          DatePicker(
            "记录时间",
            selection: $loggedAt,
            displayedComponents: [.date, .hourAndMinute]
          )
          .accessibilityIdentifier("nutrition.entry.loggedAt")
        }

        Section(draft.inputMode.nutrientSectionTitle) {
          perUnitField("卡路里", nutrient: .calories, unit: "kcal")
          perUnitField("碳水", nutrient: .carbohydrates, unit: "g")
          perUnitField("蛋白质", nutrient: .protein, unit: "g")
          perUnitField("脂肪", nutrient: .fat, unit: "g")
        }

        Section {
          totalField("卡路里", nutrient: .calories, unit: "kcal")
          totalField("碳水", nutrient: .carbohydrates, unit: "g")
          totalField("蛋白质", nutrient: .protein, unit: "g")
          totalField("脂肪", nutrient: .fat, unit: "g")
          Text(previewText)
            .font(.footnote)
            .foregroundStyle(.secondary)
        } header: {
          Text("本条记录营养总量（可手动修正）")
        } footer: {
          Text("修改份量会按当前单位营养自动缩放；手动修改总量后，再改份量会按修正后的密度计算。")
        }

        if entry == nil {
          Section {
            Toggle("同时保存为常用食物", isOn: $saveAsPreset)
              .accessibilityIdentifier("nutrition.entry.savePreset")
          } footer: {
            Text("常用食物按\(draft.inputMode == .per100g ? "每 100 克" : "每份")保存。")
          }
        }
      }
      .navigationTitle(entry == nil ? "记录饮食" : "编辑饮食")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存", action: save)
            .disabled(!isValid)
            .accessibilityIdentifier("nutrition.entry.save")
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

  private var previewText: String {
    let totals = draft.totals
    guard totals.isFinite else { return "总量预览：数值超出范围，请检查输入。" }
    return
      "总量预览：\(NutritionFormatting.number(totals.calories)) kcal · 碳水 \(NutritionFormatting.number(totals.carbohydrates))g · 蛋白质 \(NutritionFormatting.number(totals.protein))g · 脂肪 \(NutritionFormatting.number(totals.fat))g"
  }

  private func perUnitField(_ title: String, nutrient: NutrientKind, unit: String) -> some View {
    LabeledContent(title) {
      HStack {
        TextField(
          "0",
          value: Binding(
            get: { draft.perUnit.value(for: nutrient) },
            set: { draft.perUnit.setValue($0, for: nutrient) }
          ),
          format: .number.precision(.fractionLength(0...2))
        )
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .accessibilityIdentifier("nutrition.entry.perUnit.\(nutrient.rawValue)")
        Text(unit).foregroundStyle(.secondary)
      }
    }
  }

  private func totalField(_ title: String, nutrient: NutrientKind, unit: String) -> some View {
    LabeledContent(title) {
      HStack {
        TextField(
          "0",
          value: Binding(
            get: { draft.totals.value(for: nutrient) },
            set: { draft.setTotal(nutrient, to: $0) }
          ),
          format: .number.precision(.fractionLength(0...2))
        )
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .accessibilityIdentifier("nutrition.entry.total.\(nutrient.rawValue)")
        Text(unit).foregroundStyle(.secondary)
      }
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func save() {
    guard draft.isValid else {
      errorMessage = "请检查名称、份量和营养数值：数值必须为有限非负数，份量必须大于 0。"
      return
    }
    let totals = draft.totals
    let quantity = draft.canonicalQuantity

    if let entry {
      let original = FoodLogEditorSnapshot(entry: entry)
      entry.loggedAt = loggedAt
      entry.mealType = mealType
      entry.name = draft.name.trimmed
      entry.servingDescription = draft.canonicalServingDescription
      entry.quantity = quantity
      entry.calories = totals.calories
      entry.carbohydrates = totals.carbohydrates
      entry.protein = totals.protein
      entry.fat = totals.fat
      do {
        try modelContext.save()
        dismiss()
      } catch {
        original.restore(into: entry)
        errorMessage = "保存失败：\(error.localizedDescription)。修改仍保留在表单中，请重试。"
      }
    } else {
      let newEntry = draft.makeEntry(loggedAt: loggedAt, mealType: mealType)
      modelContext.insert(newEntry)
      var insertedPreset: FoodPreset?
      if saveAsPreset {
        let preset = FoodPreset(
          name: draft.name.trimmed,
          servingDescription: draft.canonicalServingDescription,
          caloriesPerServing: draft.perUnit.calories,
          carbohydratesPerServing: draft.perUnit.carbohydrates,
          proteinPerServing: draft.perUnit.protein,
          fatPerServing: draft.perUnit.fat
        )
        modelContext.insert(preset)
        insertedPreset = preset
      }
      do {
        try modelContext.save()
        dismiss()
      } catch {
        modelContext.delete(newEntry)
        if let insertedPreset { modelContext.delete(insertedPreset) }
        errorMessage = "保存失败：\(error.localizedDescription)。输入仍保留在表单中，请重试。"
      }
    }
  }
}

private struct FoodLogEditorSnapshot {
  let loggedAt: Date
  let mealTypeRaw: String
  let name: String
  let servingDescription: String
  let quantity: Double
  let calories: Double
  let carbohydrates: Double
  let protein: Double
  let fat: Double

  init(entry: FoodLogEntry) {
    loggedAt = entry.loggedAt
    mealTypeRaw = entry.mealTypeRaw
    name = entry.name
    servingDescription = entry.servingDescription
    quantity = entry.quantity
    calories = entry.calories
    carbohydrates = entry.carbohydrates
    protein = entry.protein
    fat = entry.fat
  }

  func restore(into entry: FoodLogEntry) {
    entry.loggedAt = loggedAt
    entry.mealTypeRaw = mealTypeRaw
    entry.name = name
    entry.servingDescription = servingDescription
    entry.quantity = quantity
    entry.calories = calories
    entry.carbohydrates = carbohydrates
    entry.protein = protein
    entry.fat = fat
  }
}

/// 预设 / 最近记录共用的份量表单。
private struct FoodPortionFields: View {
  @Binding var draft: FoodNutritionDraft
  @Binding var mealType: MealType
  @Binding var loggedAt: Date

  var body: some View {
    Section("记录参数") {
      LabeledContent("营养基准") {
        Text(draft.inputMode == .per100g ? "每 100 克" : draft.canonicalServingDescription)
          .foregroundStyle(.secondary)
      }
      LabeledContent(draft.inputMode.amountTitle) {
        TextField("0", value: $draft.amount, format: .number.precision(.fractionLength(0...2)))
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .accessibilityIdentifier("nutrition.portion.amount")
      }
      Picker("餐次", selection: $mealType) {
        ForEach(MealType.allCases) { Text($0.title).tag($0) }
      }
      DatePicker(
        "记录时间",
        selection: $loggedAt,
        displayedComponents: [.date, .hourAndMinute]
      )
    }
    Section("营养总量预览") {
      previewRow("卡路里", value: draft.totals.calories, unit: "kcal")
      previewRow("碳水", value: draft.totals.carbohydrates, unit: "g")
      previewRow("蛋白质", value: draft.totals.protein, unit: "g")
      previewRow("脂肪", value: draft.totals.fat, unit: "g")
    }
  }

  private func previewRow(_ title: String, value: Double, unit: String) -> some View {
    LabeledContent(title) {
      Text("\(NutritionFormatting.number(value)) \(unit)")
        .monospacedDigit()
    }
  }
}

private struct FoodPresetLogSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \FoodPreset.name)
  private var presets: [FoodPreset]

  let selectedDate: Date

  @State private var searchText = ""
  @State private var activePreset: FoodPreset?
  @State private var draft = FoodNutritionDraft()
  @State private var mealType = MealType.defaultForTime()
  @State private var loggedAt = Date.now
  @State private var errorMessage: String?

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
      List {
        if let preset = activePreset {
          Section("已选食物") {
            VStack(alignment: .leading, spacing: 3) {
              Text(preset.name)
              Text(preset.servingDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Button("重新选择") {
              activePreset = nil
            }
            .accessibilityIdentifier("nutrition.preset.reselect")
          }
          FoodPortionFields(draft: $draft, mealType: $mealType, loggedAt: $loggedAt)
          Section {
            Button("记录这条食物") { log(preset) }
              .disabled(!draft.isValid)
              .accessibilityIdentifier("nutrition.preset.log")
          } footer: {
            Text(
              FoodPortionMath.isPer100g(preset.servingDescription)
                ? "该常用食物按每 100 克记录，请输入实际克数。"
                : "请输入实际份数，营养会按份自动换算。"
            )
          }
        } else {
          Section("常用食物") {
            if presets.isEmpty {
              Text("还没有常用食物，可在资料库中创建。")
                .foregroundStyle(.secondary)
            } else if filteredPresets.isEmpty {
              Text("没有匹配的常用食物。")
                .foregroundStyle(.secondary)
            } else {
              ForEach(filteredPresets) { preset in
                Button {
                  select(preset)
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
                .accessibilityIdentifier("foodPreset.log.\(preset.id.uuidString)")
              }
            }
          }
        }
      }
      .searchable(text: $searchText, prompt: "搜索常用食物")
      .accessibilityIdentifier("nutrition.preset.search")
      .navigationTitle(activePreset == nil ? "常用食物" : "记录常用食物")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
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

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func select(_ preset: FoodPreset) {
    activePreset = preset
    draft = .fromPreset(preset)
    mealType = .defaultForTime()
    loggedAt = selectedDate.withCurrentTime()
  }

  private func log(_ preset: FoodPreset) {
    guard draft.isValid else {
      errorMessage = "请检查份量：必须为大于 0 的有限数值。"
      return
    }
    let entry = draft.makeEntry(loggedAt: loggedAt, mealType: mealType)
    modelContext.insert(entry)
    do {
      try modelContext.save()
      dismiss()
    } catch {
      modelContext.delete(entry)
      errorMessage = "保存失败：\(error.localizedDescription)。请重试。"
    }
  }
}

private struct RecentFoodPickerSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \FoodLogEntry.loggedAt, order: .reverse)
  private var entries: [FoodLogEntry]

  let selectedDate: Date

  @State private var searchText = ""
  @State private var activeItem: RecentFoodItem?
  @State private var draft = FoodNutritionDraft()
  @State private var mealType = MealType.defaultForTime()
  @State private var loggedAt = Date.now
  @State private var errorMessage: String?

  private var recentItems: [RecentFoodItem] {
    RecentFoodItem.deduplicated(from: entries).filter { $0.matches(searchText) }
  }

  var body: some View {
    NavigationStack {
      List {
        if let item = activeItem {
          Section("已选食物") {
            VStack(alignment: .leading, spacing: 3) {
              Text(item.name)
              Text(item.servingDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Button("重新选择") { activeItem = nil }
              .accessibilityIdentifier("nutrition.recent.reselect")
          }
          FoodPortionFields(draft: $draft, mealType: $mealType, loggedAt: $loggedAt)
          Section {
            Button("记录这条食物") { log(item) }
              .disabled(!draft.isValid)
              .accessibilityIdentifier("nutrition.recent.log")
          } footer: {
            Text("保存时会生成新的独立记录，不会修改原来的历史。")
          }
        } else {
          Section("最近记录") {
            if recentItems.isEmpty {
              Text("还没有可复用的历史记录。")
                .foregroundStyle(.secondary)
            } else {
              ForEach(recentItems) { item in
                Button {
                  select(item)
                } label: {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                    Text(
                      "\(item.servingDescription) · 约 \(NutritionFormatting.number(item.perUnit.calories, fraction: 0)) kcal/\(FoodPortionMath.isPer100g(item.servingDescription) ? "100 克" : "份")"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nutrition.recent.item.\(item.id)")
              }
            }
          }
        }
      }
      .searchable(text: $searchText, prompt: "搜索最近记录")
      .accessibilityIdentifier("nutrition.recent.search")
      .navigationTitle(activeItem == nil ? "最近记录" : "记录最近食物")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
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

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func select(_ item: RecentFoodItem) {
    activeItem = item
    draft = .fromRecent(item)
    mealType = .defaultForTime()
    loggedAt = selectedDate.withCurrentTime()
  }

  private func log(_ item: RecentFoodItem) {
    guard draft.isValid else {
      errorMessage = "请检查份量：必须为大于 0 的有限数值。"
      return
    }
    let entry = draft.makeEntry(loggedAt: loggedAt, mealType: mealType)
    modelContext.insert(entry)
    do {
      try modelContext.save()
      dismiss()
    } catch {
      modelContext.delete(entry)
      errorMessage = "保存失败：\(error.localizedDescription)。请重试。"
    }
  }
}

private struct MealTemplateLogSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \MealTemplate.name)
  private var templates: [MealTemplate]

  let selectedDate: Date

  @State private var activeTemplate: MealTemplate?
  @State private var quantities: [UUID: Double] = [:]
  @State private var mealType = MealType.defaultForTime()
  @State private var loggedAt = Date.now
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      List {
        if let template = activeTemplate {
          Section("记录参数") {
            Picker("餐次", selection: $mealType) {
              ForEach(MealType.allCases) { Text($0.title).tag($0) }
            }.accessibilityIdentifier("nutrition.meal.type")
            DatePicker(
              "记录时间",
              selection: $loggedAt,
              displayedComponents: [.date, .hourAndMinute]
            )
          }

          Section("食物份量（可单独调整）") {
            ForEach(template.sortedItems) { item in
              HStack {
                VStack(alignment: .leading, spacing: 3) {
                  Text(item.nameSnapshot)
                  Text(item.servingDescriptionSnapshot)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                TextField(
                  "数量",
                  value: quantityBinding(
                    for: item.id, fallback: item.quantity,
                    unitFactor: FoodPortionMath.isPer100g(item.servingDescriptionSnapshot) ? 100 : 1
                  ),
                  format: .number.precision(.fractionLength(0...2))
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 72)
                .accessibilityIdentifier("nutrition.meal.quantity.\(item.id.uuidString)")
                Text(FoodPortionMath.isPer100g(item.servingDescriptionSnapshot) ? "g" : "份")
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
          }

          Section("本条记录营养总量预览") {
            previewRow("卡路里", value: totals(for: template).calories, unit: "kcal")
            previewRow("碳水", value: totals(for: template).carbohydrates, unit: "g")
            previewRow("蛋白质", value: totals(for: template).protein, unit: "g")
            previewRow("脂肪", value: totals(for: template).fat, unit: "g")
          }

          Section {
            Button("记录这一餐") { apply(template) }
              .accessibilityIdentifier("nutrition.meal.apply")
            Button("重新选择固定餐") { activeTemplate = nil }
              .accessibilityIdentifier("nutrition.meal.reselect")
          }
        } else {
          Section("固定餐") {
            if templates.isEmpty {
              Text("还没有固定餐，可在资料库中创建。")
                .foregroundStyle(.secondary)
            } else {
              ForEach(templates) { template in
                Button {
                  select(template)
                } label: {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(template.name)
                    Text("\(template.items.count) 项食物")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(template.items.isEmpty)
                .accessibilityIdentifier("nutrition.meal.template.\(template.id.uuidString)")
              }
            }
          }
        }
      }
      .navigationTitle(activeTemplate == nil ? "记录固定餐" : "调整固定餐份量")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
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

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func select(_ template: MealTemplate) {
    activeTemplate = template
    quantities = Dictionary(
      uniqueKeysWithValues: template.sortedItems.map { ($0.id, $0.quantity) })
    mealType = .defaultForTime()
    loggedAt = selectedDate.withCurrentTime()
  }

  private func quantityBinding(for id: UUID, fallback: Double, unitFactor: Double) -> Binding<
    Double
  > {
    Binding(
      get: { (quantities[id] ?? fallback) * unitFactor },
      set: { quantities[id] = $0 / unitFactor }
    )
  }

  private func totals(for template: MealTemplate) -> NutritionValues {
    template.sortedItems.reduce(into: NutritionValues()) { result, item in
      let quantity = quantities[item.id] ?? item.quantity
      result =
        result
        + NutritionValues(
          calories: item.caloriesPerServing * quantity,
          carbohydrates: item.carbohydratesPerServing * quantity,
          protein: item.proteinPerServing * quantity,
          fat: item.fatPerServing * quantity
        )
    }
  }

  private func previewRow(_ title: String, value: Double, unit: String) -> some View {
    LabeledContent(title) {
      Text("\(NutritionFormatting.number(value)) \(unit)")
        .monospacedDigit()
    }
  }

  private func apply(_ template: MealTemplate) {
    let entries = FoodLogFactory.entries(
      from: template,
      quantities: quantities,
      mealType: mealType,
      loggedAt: loggedAt
    )
    guard !entries.isEmpty, entries.allSatisfy(\.isValid) else {
      errorMessage = "有食物的数量无效，请检查后重试（数量必须为大于 0 的有限数值）。"
      return
    }
    for entry in entries { modelContext.insert(entry) }
    do {
      try modelContext.save()
      dismiss()
    } catch {
      for entry in entries { modelContext.delete(entry) }
      errorMessage = "保存失败：\(error.localizedDescription)。请重试。"
    }
  }
}

private struct CopyMealSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \FoodLogEntry.loggedAt, order: .reverse)
  private var entries: [FoodLogEntry]

  let selectedDate: Date

  @State private var sourceDate = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
  @State private var sourceMeal: MealType = .dinner
  @State private var targetMeal = MealType.defaultForTime()
  @State private var showConfirmation = false
  @State private var errorMessage: String?

  private var sourceEntries: [FoodLogEntry] {
    entries.filter {
      Calendar.current.isDate($0.loggedAt, inSameDayAs: sourceDate) && $0.mealType == sourceMeal
    }
  }

  private var sourceTotals: NutritionValues {
    NutritionMath.totals(of: sourceEntries)
  }

  var body: some View {
    NavigationStack {
      List {
        Section("来源（复制哪一餐）") {
          DatePicker("日期", selection: $sourceDate, displayedComponents: .date)
            .accessibilityIdentifier("nutrition.copy.sourceDate")
          HStack {
            Button("昨天") {
              sourceDate = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
            }
            Spacer()
            Button("今天") { sourceDate = .now }.accessibilityIdentifier("nutrition.copy.today")
          }.buttonStyle(.borderless)
          Picker("餐次", selection: $sourceMeal) {
            ForEach(MealType.allCases) { Text($0.title).tag($0) }
          }.accessibilityIdentifier("nutrition.copy.sourceMeal")
        }

        Section("目标") {
          LabeledContent("日期") {
            Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
              .foregroundStyle(.secondary)
          }
          Picker("餐次", selection: $targetMeal) {
            ForEach(MealType.allCases) { Text($0.title).tag($0) }
          }.accessibilityIdentifier("nutrition.copy.targetMeal")
        }

        Section("预览") {
          if sourceEntries.isEmpty {
            Text("该日期和餐次没有可复制的记录。")
              .foregroundStyle(.secondary)
          } else {
            LabeledContent("记录数量") {
              Text("\(sourceEntries.count) 条").monospacedDigit()
            }
            previewRow("卡路里", value: sourceTotals.calories, unit: "kcal")
            previewRow("碳水", value: sourceTotals.carbohydrates, unit: "g")
            previewRow("蛋白质", value: sourceTotals.protein, unit: "g")
            previewRow("脂肪", value: sourceTotals.fat, unit: "g")
            Text("复制会生成全新记录并保留来源信息，原记录不会改变。")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }

        Section {
          Button("复制到目标餐次") { showConfirmation = true }
            .disabled(sourceEntries.isEmpty)
            .accessibilityIdentifier("nutrition.copy.confirm")
        }
      }
      .navigationTitle("复制某一餐")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
      }
      .confirmationDialog(
        "确认复制 \(sourceEntries.count) 条记录？",
        isPresented: $showConfirmation,
        titleVisibility: .visible
      ) {
        Button("复制") { performCopy() }
        Button("取消", role: .cancel) {}
      } message: {
        Text(
          "将复制到 \(selectedDate.formatted(date: .abbreviated, time: .omitted)) \(targetMeal.title)。"
        )
      }
      .alert("保存失败", isPresented: errorBinding) {
        Button("好", role: .cancel) { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
    }
  }

  private func previewRow(_ title: String, value: Double, unit: String) -> some View {
    LabeledContent(title) {
      Text("\(NutritionFormatting.number(value)) \(unit)")
        .monospacedDigit()
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
  }

  private func performCopy() {
    let copies = FoodLogCopier.entries(
      copying: sourceEntries,
      to: selectedDate,
      mealType: targetMeal
    )
    guard !copies.isEmpty, copies.allSatisfy(\.isValid) else {
      errorMessage = "有记录的数据无效，无法复制。"
      return
    }
    for entry in copies { modelContext.insert(entry) }
    do {
      try modelContext.save()
      dismiss()
    } catch {
      for entry in copies { modelContext.delete(entry) }
      errorMessage = "保存失败：\(error.localizedDescription)。请重试。"
    }
  }
}

extension Date {
  fileprivate func withCurrentTime(calendar: Calendar = .current) -> Date {
    FoodLogCopier.mergedDate(on: self, preservingTimeOf: .now, calendar: calendar)
  }
}
