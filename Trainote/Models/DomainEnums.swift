import Foundation

enum WorkoutStatus: String, Codable, CaseIterable {
  case inProgress
  case completed

  var title: String {
    switch self {
    case .inProgress: "进行中"
    case .completed: "已完成"
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
    case .strength: "重量 × 次数"
    case .cardio: "有氧（时长 / 距离）"
    case .repetitions: "次数"
    case .duration: "时长"
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
    case .breakfast: "早餐"
    case .lunch: "午餐"
    case .dinner: "晚餐"
    case .snack: "加餐"
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
    case .calories: "卡路里"
    case .carbohydrates: "碳水"
    case .protein: "蛋白质"
    case .fat: "脂肪"
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
