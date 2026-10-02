import Foundation
import XCTest

@testable import Trainote

final class NutritionHistoryIntegrationTests: XCTestCase {
  private let utc = TimeZone(secondsFromGMT: 0)!

  func testChangedTargetUsesEachDayHistoryRatherThanCurrentTarget() throws {
    let calendar = calendar(in: utc)
    let first = revision(
      at: date(2026, 10, 1, 10, calendar: calendar), calories: 2_000)
    let changed = revision(
      at: date(2026, 10, 3, 12, calendar: calendar), calories: 2_200)
    let history = [changed, first]
    let current = targets(calories: 2_200)

    XCTAssertNil(
      NutritionGoalHistory.targets(
        on: date(2026, 9, 30, 12, calendar: calendar), history: history,
        legacyCurrent: current, calendar: calendar))
    XCTAssertEqual(
      NutritionGoalHistory.targets(
        on: date(2026, 10, 2, 12, calendar: calendar), history: history,
        legacyCurrent: current, calendar: calendar)?.calories, 2_000)
    XCTAssertEqual(
      NutritionGoalHistory.targets(
        on: date(2026, 10, 3, 8, calendar: calendar), history: history,
        legacyCurrent: current, calendar: calendar)?.calories, 2_200)
  }

  func testSameDayUndoWinsAtLocalDayEnd() throws {
    let calendar = calendar(in: utc)
    let initial = revision(
      at: date(2026, 10, 1, 10, calendar: calendar), calories: 2_000)
    let adoption = revision(
      at: date(2026, 10, 3, 9, calendar: calendar), calories: 2_100,
      origin: .suggested)
    let undo = revision(
      at: date(2026, 10, 3, 19, calendar: calendar), calories: 2_000,
      reversesRevisionID: adoption.id)

    let target = NutritionGoalHistory.targets(
      on: date(2026, 10, 3, 8, calendar: calendar), history: [adoption, initial, undo],
      calendar: calendar)
    XCTAssertEqual(target?.calories, 2_000)
  }

  func testCalendarTimezoneDeterminesDayEnd() throws {
    let shanghai = calendar(in: TimeZone(identifier: "Asia/Shanghai")!)
    let utcCalendar = calendar(in: utc)
    let revision = revision(
      at: date(2026, 10, 3, 18, calendar: utcCalendar), calories: 2_200)
    let utcDay = date(2026, 10, 3, 12, calendar: utcCalendar)

    XCTAssertEqual(
      NutritionGoalHistory.targets(on: utcDay, history: [revision], calendar: utcCalendar)?
        .calories, 2_200)
    XCTAssertNil(
      NutritionGoalHistory.targets(on: utcDay, history: [revision], calendar: shanghai))
  }

  func testUnknownHistoryIsNotFilledFromMutableGoal() throws {
    let calendar = calendar(in: utc)
    let now = date(2026, 10, 3, 12, calendar: calendar)
    let legacy = targets(calories: 2_000)
    let yesterday = date(2026, 10, 2, 12, calendar: calendar)
    XCTAssertNil(
      NutritionGoalHistory.targets(
        on: yesterday, history: [], legacyCurrent: legacy, now: now,
        calendar: calendar))
    XCTAssertNil(
      NutritionGoalHistory.targets(
        on: now, history: [], legacyCurrent: nil, now: now,
        calendar: calendar))

    let first = revision(at: date(2026, 10, 3, 8, calendar: calendar), calories: 2_100)
    XCTAssertNil(
      NutritionGoalHistory.targets(
        on: yesterday, history: [first], legacyCurrent: legacy, now: now,
        calendar: calendar))
  }

  func testLegacyGoalOnlyAppearsTodayAndHistoricalSummaryKeepsUnknown() throws {
    let calendar = calendar(in: utc)
    let now = date(2026, 10, 3, 12, calendar: calendar)
    let legacy = NutritionGoal(
      calories: 2_000, carbohydrates: 250, protein: 150, fat: 65)
    let targets = NutritionGoalHistory.targets(
      on: now, history: [], legacyCurrent: NutritionGoalHistory.targets(from: legacy),
      now: now, calendar: calendar)
    XCTAssertEqual(targets?.calories, 2_000)

    let entry = FoodLogEntry(
      loggedAt: now, mealType: .lunch, name: "午餐", servingDescription: "1 份",
      quantity: 1, calories: 500, carbohydrates: 50, protein: 30, fat: 10)
    let known = DailyNutritionSummary(entries: [entry], historicalTargets: targets)
    XCTAssertEqual(known.remaining(for: .calories), 1_500)
    let unknown = DailyNutritionSummary(entries: [entry], historicalValues: nil)
    XCTAssertNil(unknown.goal)
    XCTAssertNil(unknown.remaining(for: .calories))
  }

  private func calendar(in timeZone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }

  private func date(
    _ year: Int, _ month: Int, _ day: Int, _ hour: Int, calendar: Calendar
  ) -> Date {
    calendar.date(
      from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }

  private func targets(calories: Double) -> NutritionTargets {
    NutritionTargets(calories: calories, carbohydrates: 250, protein: 150, fat: 65)
  }

  private func revision(
    at date: Date, calories: Double, origin: GoalRevisionOrigin = .manual,
    reversesRevisionID: UUID? = nil
  ) -> NutritionGoalRevisionValue {
    NutritionGoalRevisionValue(
      id: UUID(), effectiveAt: date, targets: targets(calories: calories), origin: origin,
      reversesRevisionID: reversesRevisionID, createdAt: date)
  }
}
