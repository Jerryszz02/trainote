import Foundation
import SwiftData
@testable import Trainote

// Frozen 1.0 storage shape. This fixture must not gain 1.1 attributes.
enum LegacyStore {
  static let modelTypes: [any PersistentModel.Type] = [
    Workout.self, WorkoutExercise.self, StrengthSet.self, CardioEntry.self,
    Routine.self, RoutineExercise.self, FoodPreset.self, MealTemplate.self,
    MealTemplateItem.self, FoodLogEntry.self, NutritionGoal.self,
  ]

  @Model
  final class Workout {
    @Attribute(.unique) var id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var statusRaw: String
    var notes: String
    var routineNameSnapshot: String?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.workout)
    var exercises: [WorkoutExercise]

    init(
      id: UUID = UUID(),
      title: String,
      startedAt: Date = .now,
      endedAt: Date? = nil,
      status: WorkoutStatus = .inProgress,
      notes: String = "",
      routineNameSnapshot: String? = nil,
      exercises: [WorkoutExercise] = []
    ) {
      self.id = id
      self.title = title
      self.startedAt = startedAt
      self.endedAt = endedAt
      self.statusRaw = status.rawValue
      self.notes = notes
      self.routineNameSnapshot = routineNameSnapshot
      self.exercises = exercises
    }

    var status: WorkoutStatus {
      get { WorkoutStatus(rawValue: statusRaw) ?? .inProgress }
      set { statusRaw = newValue.rawValue }
    }

    var sortedExercises: [WorkoutExercise] {
      exercises.sorted { lhs, rhs in
        lhs.orderIndex == rhs.orderIndex
          ? lhs.id.uuidString < rhs.id.uuidString : lhs.orderIndex < rhs.orderIndex
      }
    }

    var hasValidResult: Bool {
      exercises.contains { exercise in
        switch exercise.trackingMode {
        case .strength, .repetitions, .duration:
          exercise.strengthSets.contains {
            $0.isCompleted && $0.repetitions > 0 && $0.weightKilograms.isValidNonnegativeNumber
          }
        case .cardio:
          exercise.cardioEntries.contains { $0.isValid }
        }
      }
    }
  }

  @Model
  final class WorkoutExercise {
    @Attribute(.unique) var id: UUID
    var sourceExerciseID: String
    var nameEnSnapshot: String
    var nameZhSnapshot: String
    var orderIndex: Int
    var trackingModeRaw: String
    var notes: String
    var workout: Workout?

    @Relationship(deleteRule: .cascade, inverse: \StrengthSet.exercise)
    var strengthSets: [StrengthSet]

    @Relationship(deleteRule: .cascade, inverse: \CardioEntry.exercise)
    var cardioEntries: [CardioEntry]

    init(
      id: UUID = UUID(),
      sourceExerciseID: String,
      nameEnSnapshot: String,
      nameZhSnapshot: String,
      orderIndex: Int,
      trackingMode: TrackingMode,
      notes: String = "",
      strengthSets: [StrengthSet] = [],
      cardioEntries: [CardioEntry] = []
    ) {
      self.id = id
      self.sourceExerciseID = sourceExerciseID
      self.nameEnSnapshot = nameEnSnapshot
      self.nameZhSnapshot = nameZhSnapshot
      self.orderIndex = orderIndex
      self.trackingModeRaw = trackingMode.rawValue
      self.notes = notes
      self.strengthSets = strengthSets
      self.cardioEntries = cardioEntries
    }

    var trackingMode: TrackingMode {
      TrackingMode(rawValue: trackingModeRaw) ?? .strength
    }

    var sortedStrengthSets: [StrengthSet] {
      strengthSets.sorted { lhs, rhs in
        lhs.orderIndex == rhs.orderIndex
          ? lhs.id.uuidString < rhs.id.uuidString : lhs.orderIndex < rhs.orderIndex
      }
    }
  }

  @Model
  final class StrengthSet {
    @Attribute(.unique) var id: UUID
    var orderIndex: Int
    var weightKilograms: Double
    var repetitions: Int
    var isCompleted: Bool
    var exercise: WorkoutExercise?

    init(
      id: UUID = UUID(),
      orderIndex: Int,
      weightKilograms: Double = 0,
      repetitions: Int = 8,
      isCompleted: Bool = false
    ) {
      self.id = id
      self.orderIndex = orderIndex
      self.weightKilograms = weightKilograms
      self.repetitions = repetitions
      self.isCompleted = isCompleted
    }
  }

  @Model
  final class CardioEntry {
    @Attribute(.unique) var id: UUID
    var durationSeconds: Int
    var distanceKilometers: Double
    var calories: Double
    var exercise: WorkoutExercise?

    init(
      id: UUID = UUID(),
      durationSeconds: Int = 0,
      distanceKilometers: Double = 0,
      calories: Double = 0
    ) {
      self.id = id
      self.durationSeconds = durationSeconds
      self.distanceKilometers = distanceKilometers
      self.calories = calories
    }

    var isValid: Bool {
      durationSeconds > 0
        && distanceKilometers.isValidNonnegativeNumber
        && calories.isValidNonnegativeNumber
    }
  }

  @Model
  final class Routine {
    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \RoutineExercise.routine)
    var exercises: [RoutineExercise]

    init(
      id: UUID = UUID(),
      name: String,
      notes: String = "",
      createdAt: Date = .now,
      updatedAt: Date = .now,
      exercises: [RoutineExercise] = []
    ) {
      self.id = id
      self.name = name
      self.notes = notes
      self.createdAt = createdAt
      self.updatedAt = updatedAt
      self.exercises = exercises
    }

    var sortedExercises: [RoutineExercise] {
      exercises.sorted { lhs, rhs in
        lhs.orderIndex == rhs.orderIndex
          ? lhs.id.uuidString < rhs.id.uuidString : lhs.orderIndex < rhs.orderIndex
      }
    }
  }

  @Model
  final class RoutineExercise {
    @Attribute(.unique) var id: UUID
    var sourceExerciseID: String
    var nameEnSnapshot: String
    var nameZhSnapshot: String
    var orderIndex: Int
    var trackingModeRaw: String
    var defaultSetCount: Int
    var defaultRepetitions: Int
    var defaultWeightKilograms: Double
    var defaultDurationSeconds: Int
    var defaultDistanceKilometers: Double
    var routine: Routine?

    init(
      id: UUID = UUID(),
      sourceExerciseID: String,
      nameEnSnapshot: String,
      nameZhSnapshot: String,
      orderIndex: Int,
      trackingMode: TrackingMode,
      defaultSetCount: Int = 3,
      defaultRepetitions: Int = 8,
      defaultWeightKilograms: Double = 0,
      defaultDurationSeconds: Int = 0,
      defaultDistanceKilometers: Double = 0
    ) {
      self.id = id
      self.sourceExerciseID = sourceExerciseID
      self.nameEnSnapshot = nameEnSnapshot
      self.nameZhSnapshot = nameZhSnapshot
      self.orderIndex = orderIndex
      self.trackingModeRaw = trackingMode.rawValue
      self.defaultSetCount = defaultSetCount
      self.defaultRepetitions = defaultRepetitions
      self.defaultWeightKilograms = defaultWeightKilograms
      self.defaultDurationSeconds = defaultDurationSeconds
      self.defaultDistanceKilometers = defaultDistanceKilometers
    }

    var trackingMode: TrackingMode {
      TrackingMode(rawValue: trackingModeRaw) ?? .strength
    }

    var hasValidDefaults: Bool {
      switch trackingMode {
      case .strength, .repetitions, .duration:
        defaultSetCount > 0
          && defaultRepetitions > 0
          && defaultWeightKilograms.isValidNonnegativeNumber
      case .cardio:
        defaultDurationSeconds >= 0
          && defaultDistanceKilometers.isValidNonnegativeNumber
      }
    }
  }


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
      calories.isFinite && calories > 0
        && carbohydrates.isValidNonnegativeNumber
        && protein.isValidNonnegativeNumber
        && fat.isValidNonnegativeNumber
    }
  }
}
