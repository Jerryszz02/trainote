import Foundation

struct NutritionValues: Equatable {
  var calories: Double = 0
  var carbohydrates: Double = 0
  var protein: Double = 0
  var fat: Double = 0

  static let zero = NutritionValues()

  static func + (lhs: Self, rhs: Self) -> Self {
    Self(
      calories: lhs.calories + rhs.calories,
      carbohydrates: lhs.carbohydrates + rhs.carbohydrates,
      protein: lhs.protein + rhs.protein,
      fat: lhs.fat + rhs.fat
    )
  }

  func value(for nutrient: NutrientKind) -> Double {
    switch nutrient {
    case .calories: calories
    case .carbohydrates: carbohydrates
    case .protein: protein
    case .fat: fat
    }
  }

  mutating func setValue(_ value: Double, for nutrient: NutrientKind) {
    switch nutrient {
    case .calories: calories = value
    case .carbohydrates: carbohydrates = value
    case .protein: protein = value
    case .fat: fat = value
    }
  }

  func scaled(by factor: Double) -> NutritionValues {
    NutritionValues(
      calories: calories * factor,
      carbohydrates: carbohydrates * factor,
      protein: protein * factor,
      fat: fat * factor
    )
  }

  var isFinite: Bool {
    calories.isFinite && carbohydrates.isFinite && protein.isFinite && fat.isFinite
  }

  var isValidNonnegative: Bool {
    calories.isValidNonnegativeNumber
      && carbohydrates.isValidNonnegativeNumber
      && protein.isValidNonnegativeNumber
      && fat.isValidNonnegativeNumber
  }

  var isAllZero: Bool {
    calories == 0 && carbohydrates == 0 && protein == 0 && fat == 0
  }
}

struct DailyNutritionSummary {
  let consumed: NutritionValues
  let goal: NutritionValues?

  init(entries: [FoodLogEntry], goal: NutritionGoal?) {
    consumed = NutritionMath.totals(of: entries)
    if let goal {
      self.goal = NutritionValues(
        calories: goal.calories,
        carbohydrates: goal.carbohydrates,
        protein: goal.protein,
        fat: goal.fat
      )
    } else {
      self.goal = nil
    }
  }

  func remaining(for nutrient: NutrientKind) -> Double? {
    guard let goal else { return nil }
    return goal.value(for: nutrient) - consumed.value(for: nutrient)
  }

  func progress(for nutrient: NutrientKind) -> Double {
    guard let goal else { return 0 }
    let target = goal.value(for: nutrient)
    guard target > 0 else { return 0 }
    return min(max(consumed.value(for: nutrient) / target, 0), 1)
  }
}

enum NutritionMath {
  static func totals(of entries: [FoodLogEntry]) -> NutritionValues {
    entries.reduce(into: NutritionValues()) { result, entry in
      result =
        result
        + NutritionValues(
          calories: entry.calories,
          carbohydrates: entry.carbohydrates,
          protein: entry.protein,
          fat: entry.fat
        )
    }
  }
}

extension MealType {
  /// 默认餐次按当前时间推断，用户始终可以在表单里修改。
  static func defaultForTime(_ date: Date = .now, calendar: Calendar = .current) -> MealType {
    switch calendar.component(.hour, from: date) {
    case 5..<11: .breakfast
    case 11..<16: .lunch
    case 16..<22: .dinner
    default: .snack
    }
  }
}

/// 营养输入的基准：按份，或按每 100 克。
enum PortionInputMode: String, CaseIterable, Identifiable {
  case perServing
  case per100g

  var id: Self { self }

  var title: String {
    switch self {
    case .perServing: "按份"
    case .per100g: "按每 100 克"
    }
  }

  var nutrientSectionTitle: String {
    switch self {
    case .perServing: "每份营养"
    case .per100g: "每 100 克营养"
    }
  }

  var amountTitle: String {
    switch self {
    case .perServing: "数量（份）"
    case .per100g: "重量（克）"
    }
  }
}

/// 份量与营养之间的纯计算，供表单和测试共用。
enum FoodPortionMath {
  /// 唯一可写的每 100 克份量说明，沿用既有的 `servingDescription` 字段。
  static let per100gServingDescription = "100 g"

  /// 只有明确的哨兵描述才被识别为“每 100 克”，避免误读任意历史文本。
  private static let per100gSentinels: Set<String> = [
    "100 g", "100g", "每100克", "每 100 克",
  ]

  static func isPer100g(_ servingDescription: String) -> Bool {
    per100gSentinels.contains(servingDescription.trimmed.lowercased())
  }

  static func scale(_ values: NutritionValues, by factor: Double) -> NutritionValues {
    values.scaled(by: factor)
  }

  /// 从总量和数量反推单位密度；数量无效时返回 nil。
  static func density(from totals: NutritionValues, quantity: Double) -> NutritionValues? {
    guard quantity.isFinite, quantity > 0, totals.isValidNonnegative else { return nil }
    return NutritionValues(
      calories: totals.calories / quantity,
      carbohydrates: totals.carbohydrates / quantity,
      protein: totals.protein / quantity,
      fat: totals.fat / quantity
    )
  }
}

/// 表单用的可编辑值类型草稿，保存前不触碰 SwiftData。
struct FoodNutritionDraft: Equatable {
  var name: String
  var inputMode: PortionInputMode
  /// 按份时为份数，按每 100 克时为克数。
  var amount: Double
  /// 按份时是每份营养，按每 100 克时是每 100 克营养。
  var perUnit: NutritionValues
  var servingDescription: String
  var sourcePresetID: UUID?
  var sourceMealTemplateID: UUID?

  init(
    name: String = "",
    inputMode: PortionInputMode = .perServing,
    amount: Double = 1,
    perUnit: NutritionValues = NutritionValues(),
    servingDescription: String = "1 份",
    sourcePresetID: UUID? = nil,
    sourceMealTemplateID: UUID? = nil
  ) {
    self.name = name
    self.inputMode = inputMode
    self.amount = amount
    self.perUnit = perUnit
    self.servingDescription = servingDescription
    self.sourcePresetID = sourcePresetID
    self.sourceMealTemplateID = sourceMealTemplateID
  }

  /// 存进模型的规范数量：按份就是份数，按每 100 克则是“多少个 100 克”。
  var canonicalQuantity: Double {
    switch inputMode {
    case .perServing: amount
    case .per100g: amount / 100
    }
  }

  mutating func changeInputMode(to mode: PortionInputMode) {
    guard mode != inputMode else { return }
    let quantity = canonicalQuantity
    inputMode = mode
    amount = mode == .per100g ? quantity * 100 : quantity
    if mode == .perServing && FoodPortionMath.isPer100g(servingDescription) {
      servingDescription = "1 份"
    }
  }

  var canonicalServingDescription: String {
    switch inputMode {
    case .perServing: servingDescription.trimmed
    case .per100g: FoodPortionMath.per100gServingDescription
    }
  }

  var totals: NutritionValues {
    perUnit.scaled(by: canonicalQuantity)
  }

  var isValid: Bool {
    !name.trimmed.isEmpty
      && !canonicalServingDescription.isEmpty
      && canonicalQuantity.isFinite && canonicalQuantity > 0
      && perUnit.isValidNonnegative
      && totals.isFinite && totals.isValidNonnegative
  }

  /// 用户手动修正总量时，回写单位密度，之后改份量仍按修正后的密度缩放。
  mutating func setTotal(_ nutrient: NutrientKind, to value: Double) {
    let quantity = canonicalQuantity
    guard quantity.isFinite, quantity > 0 else { return }
    perUnit.setValue(value / quantity, for: nutrient)
  }

  func makeEntry(loggedAt: Date, mealType: MealType) -> FoodLogEntry {
    let scaledTotals = totals
    return FoodLogEntry(
      loggedAt: loggedAt,
      mealType: mealType,
      name: name.trimmed,
      servingDescription: canonicalServingDescription,
      quantity: canonicalQuantity,
      calories: scaledTotals.calories,
      carbohydrates: scaledTotals.carbohydrates,
      protein: scaledTotals.protein,
      fat: scaledTotals.fat,
      sourcePresetID: sourcePresetID,
      sourceMealTemplateID: sourceMealTemplateID
    )
  }

  static func fromPreset(_ preset: FoodPreset) -> FoodNutritionDraft {
    let per100 = FoodPortionMath.isPer100g(preset.servingDescription)
    return FoodNutritionDraft(
      name: preset.name,
      inputMode: per100 ? .per100g : .perServing,
      amount: per100 ? 100 : 1,
      perUnit: NutritionValues(
        calories: preset.caloriesPerServing,
        carbohydrates: preset.carbohydratesPerServing,
        protein: preset.proteinPerServing,
        fat: preset.fatPerServing
      ),
      servingDescription: per100
        ? FoodPortionMath.per100gServingDescription : preset.servingDescription,
      sourcePresetID: preset.id
    )
  }

  static func fromRecent(_ item: RecentFoodItem) -> FoodNutritionDraft {
    let per100 = FoodPortionMath.isPer100g(item.servingDescription)
    return FoodNutritionDraft(
      name: item.name,
      inputMode: per100 ? .per100g : .perServing,
      amount: per100 ? item.quantity * 100 : item.quantity,
      perUnit: item.perUnit,
      servingDescription: item.servingDescription,
      sourcePresetID: item.sourcePresetID,
      sourceMealTemplateID: item.sourceMealTemplateID
    )
  }

  /// 编辑已有记录：保持快照身份，按起始单位密度换算，不重新解释历史。
  static func fromEntry(_ entry: FoodLogEntry) -> FoodNutritionDraft {
    let totals = NutritionValues(
      calories: entry.calories,
      carbohydrates: entry.carbohydrates,
      protein: entry.protein,
      fat: entry.fat
    )
    let perUnit = FoodPortionMath.density(from: totals, quantity: entry.quantity) ?? totals
    let per100 = FoodPortionMath.isPer100g(entry.servingDescription)
    return FoodNutritionDraft(
      name: entry.name,
      inputMode: per100 ? .per100g : .perServing,
      amount: per100 ? entry.quantity * 100 : entry.quantity,
      perUnit: perUnit,
      servingDescription: entry.servingDescription,
      sourcePresetID: entry.sourcePresetID,
      sourceMealTemplateID: entry.sourceMealTemplateID
    )
  }
}

/// 从历史记录里抽取的可复用“最近食物”，按名称 + 份量去重。
struct RecentFoodItem: Identifiable, Equatable {
  let name: String
  let servingDescription: String
  let perUnit: NutritionValues
  let quantity: Double
  let loggedAt: Date
  let sourcePresetID: UUID?
  let sourceMealTemplateID: UUID?

  var id: String {
    "\(name.lowercased())|\(servingDescription.lowercased())"
  }

  func matches(_ query: String) -> Bool {
    let normalized = query.trimmed.lowercased()
    guard !normalized.isEmpty else { return true }
    return name.lowercased().contains(normalized)
      || servingDescription.lowercased().contains(normalized)
  }

  static func deduplicated(from entries: [FoodLogEntry]) -> [RecentFoodItem] {
    var seen = Set<String>()
    var items: [RecentFoodItem] = []
    for entry in entries.sorted(by: { $0.loggedAt > $1.loggedAt }) {
      let key = "\(entry.name.lowercased())|\(entry.servingDescription.lowercased())"
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      let totals = NutritionValues(
        calories: entry.calories,
        carbohydrates: entry.carbohydrates,
        protein: entry.protein,
        fat: entry.fat
      )
      let perUnit = FoodPortionMath.density(from: totals, quantity: entry.quantity) ?? totals
      items.append(
        RecentFoodItem(
          name: entry.name,
          servingDescription: entry.servingDescription,
          perUnit: perUnit,
          quantity: entry.quantity,
          loggedAt: entry.loggedAt,
          sourcePresetID: entry.sourcePresetID,
          sourceMealTemplateID: entry.sourceMealTemplateID
        )
      )
    }
    return items
  }
}

/// 复制历史餐次时保持快照身份、生成全新 ID，且不改动原记录。
enum FoodLogCopier {
  static func entries(
    copying sources: [FoodLogEntry],
    to date: Date,
    mealType: MealType,
    calendar: Calendar = .current
  ) -> [FoodLogEntry] {
    sources.map { source in
      FoodLogEntry(
        loggedAt: mergedDate(on: date, preservingTimeOf: source.loggedAt, calendar: calendar),
        mealType: mealType,
        name: source.name,
        servingDescription: source.servingDescription,
        quantity: source.quantity,
        calories: source.calories,
        carbohydrates: source.carbohydrates,
        protein: source.protein,
        fat: source.fat,
        sourcePresetID: source.sourcePresetID,
        sourceMealTemplateID: source.sourceMealTemplateID
      )
    }
  }

  /// 把 `day` 的年月日与 `reference` 的时分秒合成为新时间。
  static func mergedDate(
    on day: Date,
    preservingTimeOf reference: Date,
    calendar: Calendar = .current
  ) -> Date {
    let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
    let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: reference)
    var components = DateComponents()
    components.year = dayComponents.year
    components.month = dayComponents.month
    components.day = dayComponents.day
    components.hour = timeComponents.hour
    components.minute = timeComponents.minute
    components.second = timeComponents.second
    return calendar.date(from: components) ?? day
  }
}

enum NutritionFormatting {
  static func number(_ value: Double, fraction: Int = 1) -> String {
    guard value.isFinite else { return "—" }
    return value.formatted(.number.precision(.fractionLength(0...fraction)))
  }
}

enum FoodLogFactory {
  static func entry(
    from preset: FoodPreset,
    quantity: Double,
    mealType: MealType,
    loggedAt: Date
  ) -> FoodLogEntry {
    FoodLogEntry(
      loggedAt: loggedAt,
      mealType: mealType,
      name: preset.name,
      servingDescription: preset.servingDescription,
      quantity: quantity,
      calories: preset.caloriesPerServing * quantity,
      carbohydrates: preset.carbohydratesPerServing * quantity,
      protein: preset.proteinPerServing * quantity,
      fat: preset.fatPerServing * quantity,
      sourcePresetID: preset.id
    )
  }

  static func entry(
    from item: MealTemplateItem,
    quantity: Double,
    mealType: MealType,
    loggedAt: Date
  ) -> FoodLogEntry {
    FoodLogEntry(
      loggedAt: loggedAt,
      mealType: mealType,
      name: item.nameSnapshot,
      servingDescription: item.servingDescriptionSnapshot,
      quantity: quantity,
      calories: item.caloriesPerServing * quantity,
      carbohydrates: item.carbohydratesPerServing * quantity,
      protein: item.proteinPerServing * quantity,
      fat: item.fatPerServing * quantity
    )
  }

  static func entries(
    from template: MealTemplate,
    mealType: MealType,
    loggedAt: Date
  ) -> [FoodLogEntry] {
    template.sortedItems.map { item in
      FoodLogEntry(
        loggedAt: loggedAt,
        mealType: mealType,
        name: item.nameSnapshot,
        servingDescription: item.servingDescriptionSnapshot,
        quantity: item.quantity,
        calories: item.caloriesPerServing * item.quantity,
        carbohydrates: item.carbohydratesPerServing * item.quantity,
        protein: item.proteinPerServing * item.quantity,
        fat: item.fatPerServing * item.quantity,
        sourceMealTemplateID: template.id
      )
    }
  }

  /// 固定餐应用：每条数量可单独调整，应用时使用快照并关联模板来源。
  static func entries(
    from template: MealTemplate,
    quantities: [UUID: Double],
    mealType: MealType,
    loggedAt: Date
  ) -> [FoodLogEntry] {
    template.sortedItems.map { item in
      let quantity = quantities[item.id] ?? item.quantity
      return FoodLogEntry(
        loggedAt: loggedAt,
        mealType: mealType,
        name: item.nameSnapshot,
        servingDescription: item.servingDescriptionSnapshot,
        quantity: quantity,
        calories: item.caloriesPerServing * quantity,
        carbohydrates: item.carbohydratesPerServing * quantity,
        protein: item.proteinPerServing * quantity,
        fat: item.fatPerServing * quantity,
        sourceMealTemplateID: template.id
      )
    }
  }
}
