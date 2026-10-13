import Charts
import SwiftData
import SwiftUI

struct WeeklyReportView: View {
  @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
  @Query(sort: \FoodLogEntry.loggedAt, order: .reverse) private var food: [FoodLogEntry]
  @Query(sort: \NutritionGoal.updatedAt, order: .reverse) private var goals: [NutritionGoal]
  @Query(sort: \NutritionGoalRevision.effectiveAt, order: .reverse)
  private var goalRevisions: [NutritionGoalRevision]
  @State private var date = Date.now

  private var report: WeeklySummary { WeeklySummary(date: date, workouts: workouts, food: food) }
  private var lastDay: Date {
    Calendar.current.date(byAdding: .day, value: -1, to: report.interval.end)!
  }
  private var days: [DaySummary] {
    let history = goalRevisions.map(\.value)
    let legacyCurrent = NutritionGoalHistory.targets(from: goals.first)
    return (0..<7).compactMap { offset in
      guard
        let day = Calendar.current.date(byAdding: .day, value: offset, to: report.interval.start)
      else { return nil }
      let entries = food.filter { Calendar.current.isDate($0.loggedAt, inSameDayAs: day) }
      let known = entries.filter {
        $0.calories > 0 || $0.protein > 0 || $0.carbohydrates > 0 || $0.fat > 0
      }
      return DaySummary(
        date: day, calories: known.reduce(0) { $0 + $1.calories }, recorded: !known.isEmpty,
        targetCalories: NutritionGoalHistory.targets(
          on: day, history: history, legacyCurrent: legacyCurrent)?.calories,
        workouts: workouts.filter {
          $0.status == .completed && Calendar.current.isDate($0.startedAt, inSameDayAs: day)
        }.count)
    }
  }

  var body: some View {
    List {
      Section {
        HStack {
          Button(L10n.text("core.previous.week"), systemImage: "chevron.left") { moveWeek(-1) }
            .labelStyle(.iconOnly).accessibilityIdentifier("report.previousWeek")
          Spacer()
          VStack(spacing: 3) {
            Text(
              "\(report.interval.start.formatted(.dateTime.month().day().locale(L10n.locale))) – \(lastDay.formatted(.dateTime.month().day().locale(L10n.locale)))"
            )
            .font(.headline)
            Text(L10n.text("core.monday.to.sunday")).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button(L10n.text("core.next.week"), systemImage: "chevron.right") { moveWeek(1) }
            .labelStyle(.iconOnly)
            .disabled(report.interval.contains(.now))
        }
        if !report.interval.contains(.now) {
          Button(L10n.text("core.back.to.this.week")) { date = .now }
        }
      }

      Section(L10n.text("core.training.totals")) {
        LabeledContent(L10n.text("core.completed.workouts"), value: L10n.text("core.workouts", report.trainingCount))
        LabeledContent(L10n.text("core.completed.sets"), value: L10n.text("core.sets", report.completedSetCount))
        LabeledContent(
          L10n.text("core.strength.training.volume"),
          value: L10n.text("core.kg.reps" , String(describing: report.volume.formatted(.number.precision(.fractionLength(0...1)).locale(L10n.locale)))))
        Text(L10n.text("core.volume.includes.completed.valid.weight.reps.sets.only.your.first.result.establishes.a"))
          .font(.caption).foregroundStyle(.secondary)
      }

      Section(L10n.text("core.this.week.s.personal.records")) {
        if report.personalRecords.isEmpty {
          Text(L10n.text("core.no.new.weight.or.volume.records.this.week.every.valid.record.becomes.a.reference.for."))
            .foregroundStyle(.secondary)
        } else {
          ForEach(report.personalRecords) { record in
            VStack(alignment: .leading, spacing: 5) {
              Label("\(record.exerciseName) · \(record.title)", systemImage: "trophy.fill")
                .font(.subheadline.bold())
              Text(
                "\(record.previousValue.formatted(.number.precision(.fractionLength(0...1)).locale(L10n.locale))) → \(record.value.formatted(.number.precision(.fractionLength(0...1)).locale(L10n.locale))) \(record.unit)"
              )
              .monospacedDigit()
            }
            .padding(.vertical, 4)
          }
        }
      }

      Section(L10n.text("core.food.records")) {
        LabeledContent(L10n.text("core.days.with.records"), value: L10n.text("core.days", report.nutritionDays))
        LabeledContent(L10n.text("core.days.with.available.goals"), value: L10n.text("core.7.days", days.filter { $0.targetCalories != nil }.count))
        if let calories = report.averageCalories, let protein = report.averageProtein {
          LabeledContent(
            L10n.text("core.average.recorded.calories.per.day"), value: "\(calories.formatted(.number.precision(.fractionLength(0)).locale(L10n.locale))) kcal")
          LabeledContent(
            L10n.text("core.average.recorded.protein.per.day"), value: "\(protein.formatted(.number.precision(.fractionLength(0...1)).locale(L10n.locale))) g")
          Chart(days.filter(\.recorded)) { day in
            BarMark(x: .value(L10n.text("core.date"), day.date, unit: .day), y: .value(L10n.text("core.recorded.calories"), day.calories))
              .foregroundStyle(Color.accentColor)
              .accessibilityLabel(day.date.formatted(.dateTime.month().day().locale(L10n.locale)))
              .accessibilityValue(
                L10n.text("core.kcal" , String(describing: day.calories.formatted(.number.precision(.fractionLength(0)).locale(L10n.locale)))))
          }
          .chartXScale(domain: report.interval.start...report.interval.end)
          .frame(height: 160)
        } else {
          Text(L10n.text("core.no.food.records.with.nutrition.values.this.week"))
            .foregroundStyle(.secondary)
        }
        Text(L10n.text("core.averages.use.only.the.days.with.recorded.nutrition.values.goals.reflect.each.day.s.hi", report.nutritionValueDays))
          .font(.caption).foregroundStyle(.secondary)
        if report.unknownFoodCount > 0 {
          Label(L10n.text("core.food.entries.have.no.nutrition.values", report.unknownFoodCount), systemImage: "info.circle")
            .font(.caption)
        }
      }

      Section(L10n.text("core.daily.overview")) {
        ForEach(days) { day in
          HStack {
            Text(day.date.formatted(.dateTime.weekday(.abbreviated).month().day().locale(L10n.locale)))
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
              Text(
                day.recorded
                  ? "\(day.calories.formatted(.number.precision(.fractionLength(0)).locale(L10n.locale))) kcal"
                  : L10n.text("core.nutrition.not.recorded"))
              Text(
                day.targetCalories.map {
                  L10n.text("core.goal.kcal" , String(describing: $0.formatted(.number.precision(.fractionLength(0)).locale(L10n.locale))))
                } ?? (goals.isEmpty && goalRevisions.isEmpty ? L10n.text("core.no.goal.set") : L10n.text("core.no.historical.goal"))
              )
              .font(.caption).foregroundStyle(.secondary)
              Text(L10n.text("core.workouts", day.workouts)).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .navigationTitle(L10n.text("core.weekly.review"))
    .accessibilityIdentifier("weeklyReport")
  }

  private func moveWeek(_ amount: Int) {
    date = Calendar.current.date(byAdding: .weekOfYear, value: amount, to: date) ?? date
  }
}

private struct DaySummary: Identifiable {
  let date: Date
  let calories: Double
  let recorded: Bool
  let targetCalories: Double?
  let workouts: Int
  var id: Date { date }
}
