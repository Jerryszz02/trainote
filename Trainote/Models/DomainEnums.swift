import Foundation

enum WorkoutStatus: String, Codable, CaseIterable {
  case inProgress
  case completed

  var title: String {
    switch self {
    case .inProgress: L10n.text("domain.in.progress")
    case .completed: L10n.text("domain.completed")
    }
  }
}

enum TrackingMode: String, Codable, CaseIterable, Identifiable {
  case strength
  case cardio
  case repetitions
  case duration

  var id: Self { self }

  var title: String {
    switch self {
    case .strength: L10n.text("domain.weight.reps")
    case .cardio: L10n.text("domain.cardio.duration.distance")
    case .repetitions: L10n.text("domain.reps")
    case .duration: L10n.text("domain.duration")
    }
  }

  var usesSets: Bool { self != .cardio }

  var systemImage: String {
    switch self {
    case .strength: "dumbbell.fill"
    case .cardio: "figure.run"
    case .repetitions: "repeat"
    case .duration: "timer"
    }
  }
}

enum MealType: String, Codable, CaseIterable, Identifiable {
  case breakfast
  case lunch
  case dinner
  case snack

  var id: Self { self }

  var title: String {
    switch self {
    case .breakfast: L10n.text("domain.breakfast")
    case .lunch: L10n.text("domain.lunch")
    case .dinner: L10n.text("domain.dinner")
    case .snack: L10n.text("domain.snack")
    }
  }

  var systemImage: String {
    switch self {
    case .breakfast: "sunrise.fill"
    case .lunch: "sun.max.fill"
    case .dinner: "moon.stars.fill"
    case .snack: "carrot.fill"
    }
  }
}

enum NutrientKind: String, CaseIterable, Identifiable {
  case calories
  case carbohydrates
  case protein
  case fat

  var id: Self { self }

  var title: String {
    switch self {
    case .calories: L10n.text("domain.calories")
    case .carbohydrates: L10n.text("domain.carbs")
    case .protein: L10n.text("domain.protein")
    case .fat: L10n.text("domain.fat")
    }
  }

  var unit: String { self == .calories ? "kcal" : "g" }
}

extension Double {
  var isValidNonnegativeNumber: Bool { isFinite && (0...1_000_000).contains(self) }
}

extension String {
  var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
