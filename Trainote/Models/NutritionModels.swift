import Foundation
import SwiftData

@Model
final class FoodPreset {
  @Attribute(.unique) var id: UUID
  var name: String
  var servingDescription: String
  var caloriesPerServing: Double
  var carbohydratesPerServing: Double
  var proteinPerServing: Double
  var fatPerServing: Double
  var createdAt: Date
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    name: String,
    servingDescription: String = "1 份",
    caloriesPerServing: Double,
    carbohydratesPerServing: Double,
    proteinPerServing: Double,
    fatPerServing: Double,
    createdAt: Date = .now,
    updatedAt: Date = .now
  ) {
    self.id = id
    self.name = name
    self.servingDescription = servingDescription
    self.caloriesPerServing = caloriesPerServing
    self.carbohydratesPerServing = carbohydratesPerServing
    self.proteinPerServing = proteinPerServing
    self.fatPerServing = fatPerServing
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  var isValid: Bool {
    !name.trimmed.isEmpty
      && !servingDescription.trimmed.isEmpty
      && caloriesPerServing.isValidNonnegativeNumber
      && carbohydratesPerServing.isValidNonnegativeNumber
      && proteinPerServing.isValidNonnegativeNumber
      && fatPerServing.isValidNonnegativeNumber
  }
}

@Model
final class MealTemplate {
  @Attribute(.unique) var id: UUID
  var name: String
  var notes: String
  var createdAt: Date
  var updatedAt: Date

  @Relationship(deleteRule: .cascade, inverse: \MealTemplateItem.template)
  var items: [MealTemplateItem]

  init(
    id: UUID = UUID(),
    name: String,
    notes: String = "",
    createdAt: Date = .now,
    updatedAt: Date = .now,
    items: [MealTemplateItem] = []
  ) {
    self.id = id
    self.name = name
    self.notes = notes
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.items = items
  }

  var sortedItems: [MealTemplateItem] {
    items.sorted { lhs, rhs in
      lhs.orderIndex == rhs.orderIndex
        ? lhs.id.uuidString < rhs.id.uuidString : lhs.orderIndex < rhs.orderIndex
    }
  }

  var isValid: Bool {
    !name.trimmed.isEmpty && !items.isEmpty && items.allSatisfy(\.isValid)
  }
}

@Model
final class MealTemplateItem {
  @Attribute(.unique) var id: UUID
  var orderIndex: Int
  var nameSnapshot: String
  var servingDescriptionSnapshot: String
  var quantity: Double
  var caloriesPerServing: Double
  var carbohydratesPerServing: Double
  var proteinPerServing: Double
  var fatPerServing: Double
  var template: MealTemplate?

  init(
    id: UUID = UUID(),
    orderIndex: Int,
    nameSnapshot: String,
    servingDescriptionSnapshot: String,
    quantity: Double,
    caloriesPerServing: Double,
    carbohydratesPerServing: Double,
    proteinPerServing: Double,
    fatPerServing: Double
  ) {
    self.id = id
    self.orderIndex = orderIndex
    self.nameSnapshot = nameSnapshot
    self.servingDescriptionSnapshot = servingDescriptionSnapshot
    self.quantity = quantity
    self.caloriesPerServing = caloriesPerServing
    self.carbohydratesPerServing = carbohydratesPerServing
    self.proteinPerServing = proteinPerServing
    self.fatPerServing = fatPerServing
  }

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

@Model
final class FoodLogEntry {
  @Attribute(.unique) var id: UUID
  var loggedAt: Date
  var mealTypeRaw: String
  var name: String
  var servingDescription: String
  var quantity: Double
  var calories: Double
  var carbohydrates: Double
  var protein: Double
  var fat: Double
  var sourcePresetID: UUID?
  var sourceMealTemplateID: UUID?

  init(
    id: UUID = UUID(),
    loggedAt: Date,
    mealType: MealType,
    name: String,
    servingDescription: String,
    quantity: Double,
    calories: Double,
    carbohydrates: Double,
    protein: Double,
    fat: Double,
    sourcePresetID: UUID? = nil,
    sourceMealTemplateID: UUID? = nil
  ) {
    self.id = id
    self.loggedAt = loggedAt
    self.mealTypeRaw = mealType.rawValue
    self.name = name
    self.servingDescription = servingDescription
    self.quantity = quantity
    self.calories = calories
    self.carbohydrates = carbohydrates
    self.protein = protein
    self.fat = fat
    self.sourcePresetID = sourcePresetID
    self.sourceMealTemplateID = sourceMealTemplateID
  }

  var mealType: MealType {
    get { MealType(rawValue: mealTypeRaw) ?? .snack }
    set { mealTypeRaw = newValue.rawValue }
  }

  var isValid: Bool {
    !name.trimmed.isEmpty
      && !servingDescription.trimmed.isEmpty
      && quantity.isFinite && quantity > 0
      && calories.isValidNonnegativeNumber
      && carbohydrates.isValidNonnegativeNumber
      && protein.isValidNonnegativeNumber
      && fat.isValidNonnegativeNumber
  }
}

@Model
final class NutritionGoal {
  @Attribute(.unique) var id: UUID
  var calories: Double
  var carbohydrates: Double
  var protein: Double
  var fat: Double
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    calories: Double,
    carbohydrates: Double,
    protein: Double,
    fat: Double,
    updatedAt: Date = .now
  ) {
    self.id = id
    self.calories = calories
    self.carbohydrates = carbohydrates
    self.protein = protein
    self.fat = fat
    self.updatedAt = updatedAt
  }

  var isValid: Bool {
    calories.isValidNonnegativeNumber && calories > 0
      && carbohydrates.isValidNonnegativeNumber
      && protein.isValidNonnegativeNumber
      && fat.isValidNonnegativeNumber
  }
}
