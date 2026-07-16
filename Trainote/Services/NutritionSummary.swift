import Foundation

struct NutritionValues: Equatable {
  var calories: Double = 0
  var carbohydrates: Double = 0
  var protein: Double = 0
  var fat: Double = 0

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
}

struct DailyNutritionSummary {
  let consumed: NutritionValues
  let goal: NutritionValues?

  init(entries: [FoodLogEntry], goal: NutritionGoal?) {
    consumed = entries.reduce(into: NutritionValues()) { result, entry in
      result =
        result
        + NutritionValues(
          calories: entry.calories,
          carbohydrates: entry.carbohydrates,
          protein: entry.protein,
          fat: entry.fat
        )
    }
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
}
