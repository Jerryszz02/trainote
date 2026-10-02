import Foundation

/// Resolve a target for a calendar day without projecting today's mutable goal into the past.
enum NutritionGoalHistory {
  static func targets(
    on day: Date,
    history: [NutritionGoalRevisionValue],
    legacyCurrent: NutritionTargets? = nil,
    now: Date = .now,
    calendar: Calendar = .current
  ) -> NutritionTargets? {
    guard let interval = calendar.dateInterval(of: .day, for: day) else { return nil }
    let lastInstant = Date(
      timeIntervalSinceReferenceDate: interval.end.timeIntervalSinceReferenceDate.nextDown)
    if let revision = TrendHistory.effective(at: lastInstant, history: history) {
      return revision.targets
    }
    guard history.isEmpty, calendar.isDate(day, inSameDayAs: now) else { return nil }
    return legacyCurrent
  }

  static func targets(from goal: NutritionGoal?) -> NutritionTargets? {
    guard let goal else { return nil }
    return NutritionTargets(
      calories: goal.calories, carbohydrates: goal.carbohydrates,
      protein: goal.protein, fat: goal.fat)
  }
}
