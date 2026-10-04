import Foundation

/// Versioned engineering starting values (P), not validated physiological constants.
struct TrendRules: Codable, Equatable, Sendable {
  let version = "trend-p-v1"
  let smoothingDays = 7.0
  let slopeWindowDays = 21
  let minimumSpanDays = 14.0
  let minimumWeightDays = 8
  let minimumWeightDaysPerWeek = 3
  let dietWindowDays = 14
  let minimumCompleteDietDays = 12
  let reviewDays = 7
  let maximumStepCalories = 100.0
  let maximumStepFraction = 0.05
  let adherenceTolerance = 0.15
  let minimumPriorFraction = 0.8
  let fatFraction = 0.25
  let morningHours = 4..<12
  let minimumOutlierDistance = 3.0
  let outlierMADMultiplier = 6.0
  let outlierNeighbourDays = 10.0
  let minimumOutlierNeighbours = 5
  let admissibleWeight = 25.0...350.0
  let generalFitnessBMI = 18.5..<30.0
  let formulaAgeRange = 18...78

  func activityFactor(_ level: ActivityLevel) -> Double {
    switch level {
    case .sedentary: return 1.2
    case .light: return 1.4
    case .moderate: return 1.6
    case .high: return 1.8
    }
  }
  func initialMultiplier(_ direction: GoalDirection) -> Double {
    switch direction {
    case .maintain: return 1
    case .lose: return 0.85
    case .gain: return 1.05
    }
  }
  func targetRate(_ direction: GoalDirection) -> Double {
    switch direction {
    case .maintain: return 0
    case .lose: return -0.5
    case .gain: return 0.15
    }
  }
  func rateTolerance(_ direction: GoalDirection) -> Double {
    direction == .gain ? 0.10 : 0.15
  }
  func proteinPerKilogram(_ direction: GoalDirection) -> Double {
    direction == .lose ? 2.0 : 1.8
  }
  func permits(rate: Double, direction: GoalDirection) -> Bool {
    switch direction {
    case .lose: return (-1.0 ... -0.1).contains(rate)
    case .gain: return (0.05...0.5).contains(rate)
    case .maintain: return abs(rate) <= 0.15
    }
  }
}

/// Precision is retained in persisted targets; rounding is presentation-only.
enum TrendNutrition {
  static func targets(calories: Double, protein: Double, fatFraction: Double = 0.25)
    -> NutritionTargets?
  {
    guard calories.isFinite, calories > 0, protein.isFinite, protein > 0,
      (0.20...0.35).contains(fatFraction)
    else { return nil }
    let fat = calories * fatFraction / 9
    let carbohydrates = (calories - 4 * protein - 9 * fat) / 4
    guard carbohydrates.isFinite, carbohydrates >= 0 else { return nil }
    return .init(calories: calories, carbohydrates: carbohydrates, protein: protein, fat: fat)
  }
  static func displayed(_ value: NutritionTargets) -> NutritionTargets {
    .init(
      calories: value.calories.rounded(),
      carbohydrates: value.carbohydrates.rounded(), protein: value.protein.rounded(),
      fat: value.fat.rounded())
  }
}

enum TrendHistory {
  static func baseline(in input: AnalysisInput, version: String = TrendRules().version)
    -> NutritionGoalRevisionValue?
  {
    guard let profile = input.profile else { return nil }
    return ordered(input.goalHistory).first {
      $0.calculationVersion == version && $0.origin != .manual && $0.reversesRevisionID == nil
        && $0.createdAt >= profile.updatedAt && !isReversed($0, history: input.goalHistory)
    }
  }
  static func needsBaselineRebuild(_ input: AnalysisInput, version: String = TrendRules().version)
    -> Bool
  {
    guard let profile = input.profile, baseline(in: input, version: version) == nil else {
      return false
    }
    return input.goalHistory.contains {
      $0.calculationVersion == version && $0.createdAt < profile.updatedAt
    }
  }
  static func ordered(_ history: [NutritionGoalRevisionValue]) -> [NutritionGoalRevisionValue] {
    history.sorted {
      if $0.effectiveAt != $1.effectiveAt { return $0.effectiveAt < $1.effectiveAt }
      if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
      return $0.id.uuidString < $1.id.uuidString
    }
  }
  /// Never backfill a past day with today's mutable legacy target.
  static func effective(at date: Date, history: [NutritionGoalRevisionValue])
    -> NutritionGoalRevisionValue?
  {
    ordered(history).last { $0.effectiveAt <= date }
  }
  static func isReversed(
    _ revision: NutritionGoalRevisionValue,
    history: [NutritionGoalRevisionValue]
  ) -> Bool {
    history.contains { $0.reversesRevisionID == revision.id }
  }
}

struct TrendCalendar {
  let calendar: Calendar
  init?(identifier: String) {
    guard let zone = TimeZone(identifier: identifier) else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    self.calendar = calendar
  }
  var timeZone: TimeZone { calendar.timeZone }
  func matches(_ identifier: String) -> Bool { TimeZone(identifier: identifier) == timeZone }
  func start(_ date: Date) -> Date { calendar.startOfDay(for: date) }
  func adding(days: Int, to date: Date) -> Date {
    calendar.date(byAdding: .day, value: days, to: date)!
  }
  func key(_ date: Date) -> String { AnalysisFingerprint.localDate(date, timeZone: timeZone) }
  func date(_ key: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    guard let date = formatter.date(from: key), self.key(date) == key else { return nil }
    return date
  }
}
