import SwiftData
import SwiftUI

private enum NutritionSheet: Identifiable {
  case entry(FoodLogEntry?)
  case presetPicker
  case mealPicker

  var id: String {
    switch self {
    case .entry(let entry): "entry-\(entry?.id.uuidString ?? "new")"
    case .presetPicker: "preset-picker"
    case .mealPicker: "meal-picker"
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

  let addRequest: Int

  private var dayEntries: [FoodLogEntry] {
    entries.filter { Calendar.current.isDate($0.loggedAt, inSameDayAs: selectedDate) }
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

      ForEach(MealType.allCases) { mealType in
        mealSection(mealType)
      }

      if dayEntries.isEmpty {
        ContentUnavailableView(
          "当天没有饮食记录",
          systemImage: "fork.knife.circle",
          description: Text("点击右上角加号记录食物、常用食物或固定餐。")
        )
        .frame(maxWidth: .infinity)
      }
    }
    .navigationTitle("饮食")
    .onChange(of: addRequest, initial: true) { _, newValue in
      if newValue > 0 {
        presentedSheet = .entry(nil)
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("直接记录", systemImage: "square.and.pencil") {
            presentedSheet = .entry(nil)
          }
          Button("从常用食物记录", systemImage: "star.fill") {
            presentedSheet = .presetPicker
          }
          Button("记录固定餐", systemImage: "list.bullet.rectangle") {
            presentedSheet = .mealPicker
          }
        } label: {
          Label("添加饮食", systemImage: "plus")
        }
        .accessibilityIdentifier("nutrition.add")
      }
    }
    .sheet(item: $presentedSheet) { sheet in
      switch sheet {
      case .entry(let entry):
        FoodEntryEditor(date: selectedDate, entry: entry)
      case .presetPicker:
        FoodPresetLogSheet(date: selectedDate)
      case .mealPicker:
        MealTemplateLogSheet(date: selectedDate)
      }
    }
    .alert("删除这条饮食记录？", isPresented: deletionAlertBinding, presenting: pendingDeletion) { entry in
      Button("删除", role: .destructive) {
        modelContext.delete(entry)
        try? modelContext.save()
        pendingDeletion = nil
      }
      Button("取消", role: .cancel) { pendingDeletion = nil }
    } message: { _ in
      Text("当天营养汇总会立即更新。")
    }
  }

  @ViewBuilder
  private func mealSection(_ mealType: MealType) -> some View {
    let mealEntries = dayEntries.filter { $0.mealType == mealType }
    if !mealEntries.isEmpty {
      Section {
        ForEach(mealEntries) { entry in
          Button {
            presentedSheet = .entry(entry)
          } label: {
            FoodLogRow(entry: entry)
          }
          .buttonStyle(.plain)
          .swipeActions {
            Button("删除", role: .destructive) { pendingDeletion = entry }
          }
        }
      } header: {
        Label(mealType.title, systemImage: mealType.systemImage)
      }
    }
  }

  private var deletionAlertBinding: Binding<Bool> {
    Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })
  }
}

private struct FoodLogRow: View {
  let entry: FoodLogEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(entry.name).font(.body.weight(.medium))
        Spacer()
        Text("\(entry.calories, format: .number.precision(.fractionLength(0))) kcal")
          .font(.subheadline.monospacedDigit())
      }
      Text(
        "\(entry.quantity, format: .number.precision(.fractionLength(0...2))) × \(entry.servingDescription)"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      Text(
        "碳水 \(entry.carbohydrates, format: .number.precision(.fractionLength(0...1)))g · 蛋白质 \(entry.protein, format: .number.precision(.fractionLength(0...1)))g · 脂肪 \(entry.fat, format: .number.precision(.fractionLength(0...1)))g"
      )
      .font(.caption2)
      .foregroundStyle(.tertiary)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

private struct FoodEntryEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  let date: Date
  let entry: FoodLogEntry?

  @State private var name: String
  @State private var servingDescription: String
  @State private var quantity: Double
  @State private var calories: Double
  @State private var carbohydrates: Double
  @State private var protein: Double
  @State private var fat: Double
  @State private var mealType: MealType
  @State private var saveAsPreset = false

  init(date: Date, entry: FoodLogEntry?) {
    self.date = date
    self.entry = entry
    _name = State(initialValue: entry?.name ?? "")
    _servingDescription = State(initialValue: entry?.servingDescription ?? "1 份")
    _quantity = State(initialValue: entry?.quantity ?? 1)
    _calories = State(initialValue: entry?.calories ?? 0)
    _carbohydrates = State(initialValue: entry?.carbohydrates ?? 0)
    _protein = State(initialValue: entry?.protein ?? 0)
    _fat = State(initialValue: entry?.fat ?? 0)
    _mealType = State(initialValue: entry?.mealType ?? .breakfast)
  }

  private var isValid: Bool {
    !name.trimmed.isEmpty
      && !servingDescription.trimmed.isEmpty
      && quantity.isFinite && quantity > 0
      && calories.isValidNonnegativeNumber
      && carbohydrates.isValidNonnegativeNumber
      && protein.isValidNonnegativeNumber
      && fat.isValidNonnegativeNumber
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("食物") {
          TextField("名称", text: $name)
            .accessibilityIdentifier("nutrition.entry.name")
          TextField("份量说明", text: $servingDescription)
          LabeledContent("数量") {
            TextField("1", value: $quantity, format: .number.precision(.fractionLength(0...2)))
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
          }
          Picker("餐次", selection: $mealType) {
            ForEach(MealType.allCases) { Text($0.title).tag($0) }
          }
        }

        Section("本条记录的营养总量") {
          nutritionField("卡路里", value: $calories, unit: "kcal")
          nutritionField("碳水", value: $carbohydrates, unit: "g")
          nutritionField("蛋白质", value: $protein, unit: "g")
          nutritionField("脂肪", value: $fat, unit: "g")
        }

        if entry == nil {
          Section {
            HStack {
              Text("同时保存为常用食物")
              Spacer()
              Toggle("同时保存为常用食物", isOn: $saveAsPreset)
                .labelsHidden()
            }
          } footer: {
            Text("常用食物按每份保存；如果数量大于 1，Trainote 会自动换算。")
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
      }
    }
  }

  private func nutritionField(_ title: String, value: Binding<Double>, unit: String) -> some View {
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
    let loggedAt = date.withCurrentTime()
    if let entry {
      entry.loggedAt = loggedAt
      entry.name = name.trimmed
      entry.servingDescription = servingDescription.trimmed
      entry.quantity = quantity
      entry.calories = calories
      entry.carbohydrates = carbohydrates
      entry.protein = protein
      entry.fat = fat
      entry.mealType = mealType
    } else {
      modelContext.insert(
        FoodLogEntry(
          loggedAt: loggedAt,
          mealType: mealType,
          name: name.trimmed,
          servingDescription: servingDescription.trimmed,
          quantity: quantity,
          calories: calories,
          carbohydrates: carbohydrates,
          protein: protein,
          fat: fat
        )
      )
      if saveAsPreset {
        modelContext.insert(
          FoodPreset(
            name: name.trimmed,
            servingDescription: servingDescription.trimmed,
            caloriesPerServing: calories / quantity,
            carbohydratesPerServing: carbohydrates / quantity,
            proteinPerServing: protein / quantity,
            fatPerServing: fat / quantity
          )
        )
      }
    }
    try? modelContext.save()
    dismiss()
  }
}

private struct FoodPresetLogSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \FoodPreset.name)
  private var presets: [FoodPreset]

  let date: Date
  @State private var mealType: MealType = .breakfast
  @State private var quantity = 1.0

  var body: some View {
    NavigationStack {
      List {
        Section("记录参数") {
          Picker("餐次", selection: $mealType) {
            ForEach(MealType.allCases) { Text($0.title).tag($0) }
          }
          LabeledContent("数量") {
            TextField("1", value: $quantity, format: .number.precision(.fractionLength(0...2)))
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
          }
        }

        Section("常用食物") {
          if presets.isEmpty {
            Text("还没有常用食物，可在资料库中创建。")
              .foregroundStyle(.secondary)
          } else {
            ForEach(presets) { preset in
              Button {
                log(preset)
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
              .disabled(!quantity.isFinite || quantity <= 0)
              .accessibilityIdentifier("foodPreset.log.\(preset.id.uuidString)")
            }
          }
        }
      }
      .navigationTitle("常用食物")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
      }
    }
  }

  private func log(_ preset: FoodPreset) {
    guard quantity.isFinite, quantity > 0 else { return }
    modelContext.insert(
      FoodLogFactory.entry(
        from: preset,
        quantity: quantity,
        mealType: mealType,
        loggedAt: date.withCurrentTime()
      )
    )
    try? modelContext.save()
    dismiss()
  }
}

private struct MealTemplateLogSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \MealTemplate.name)
  private var templates: [MealTemplate]

  let date: Date
  @State private var mealType: MealType = .breakfast

  var body: some View {
    NavigationStack {
      List {
        Section {
          Picker("餐次", selection: $mealType) {
            ForEach(MealType.allCases) { Text($0.title).tag($0) }
          }
        }

        Section("固定餐") {
          if templates.isEmpty {
            Text("还没有固定餐，可在资料库中创建。")
              .foregroundStyle(.secondary)
          } else {
            ForEach(templates) { template in
              Button {
                log(template)
              } label: {
                VStack(alignment: .leading, spacing: 3) {
                  Text(template.name)
                  Text("\(template.items.count) 项食物")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              .buttonStyle(.plain)
              .disabled(template.items.isEmpty)
            }
          }
        }
      }
      .navigationTitle("记录固定餐")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
      }
    }
  }

  private func log(_ template: MealTemplate) {
    let entries = FoodLogFactory.entries(
      from: template,
      mealType: mealType,
      loggedAt: date.withCurrentTime()
    )
    guard !entries.isEmpty, entries.allSatisfy(\.isValid) else { return }
    for entry in entries { modelContext.insert(entry) }
    do {
      try modelContext.save()
      dismiss()
    } catch {
      for entry in entries { modelContext.delete(entry) }
    }
  }
}

extension Date {
  fileprivate func withCurrentTime(calendar: Calendar = .current) -> Date {
    let day = calendar.dateComponents([.year, .month, .day], from: self)
    let time = calendar.dateComponents([.hour, .minute, .second], from: .now)
    var components = DateComponents()
    components.year = day.year
    components.month = day.month
    components.day = day.day
    components.hour = time.hour
    components.minute = time.minute
    components.second = time.second
    return calendar.date(from: components) ?? self
  }
}
