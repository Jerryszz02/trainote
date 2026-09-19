import Charts
import SwiftData
import SwiftUI

struct WeeklyReportView: View {
  @Query(sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
  @Query(sort: \FoodLogEntry.loggedAt, order: .reverse) private var food: [FoodLogEntry]
  @State private var date = Date.now

  private var report: WeeklySummary { WeeklySummary(date: date, workouts: workouts, food: food) }
  private var lastDay: Date {
    Calendar.current.date(byAdding: .day, value: -1, to: report.interval.end)!
  }
  private var days: [DaySummary] {
    (0..<7).compactMap { offset in
      guard
        let day = Calendar.current.date(byAdding: .day, value: offset, to: report.interval.start)
      else { return nil }
      let entries = food.filter { Calendar.current.isDate($0.loggedAt, inSameDayAs: day) }
      let known = entries.filter {
        $0.calories > 0 || $0.protein > 0 || $0.carbohydrates > 0 || $0.fat > 0
      }
      return DaySummary(
        date: day, calories: known.reduce(0) { $0 + $1.calories }, recorded: !known.isEmpty,
        workouts: workouts.filter {
          $0.status == .completed && Calendar.current.isDate($0.startedAt, inSameDayAs: day)
        }.count)
    }
  }

  var body: some View {
    List {
      Section {
        HStack {
          Button("上一周", systemImage: "chevron.left") { moveWeek(-1) }
            .labelStyle(.iconOnly).accessibilityIdentifier("report.previousWeek")
          Spacer()
          VStack(spacing: 3) {
            Text(
              "\(report.interval.start.formatted(.dateTime.month().day())) – \(lastDay.formatted(.dateTime.month().day()))"
            )
            .font(.headline)
            Text("周一至周日").font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button("下一周", systemImage: "chevron.right") { moveWeek(1) }
            .labelStyle(.iconOnly)
            .disabled(report.interval.contains(.now))
        }
        if !report.interval.contains(.now) {
          Button("回到本周") { date = .now }
        }
      }

      Section("训练积累") {
        LabeledContent("完成训练", value: "\(report.trainingCount) 次")
        LabeledContent("完成组数", value: "\(report.completedSetCount) 组")
        LabeledContent(
          "负重训练容量",
          value: "\(report.volume.formatted(.number.precision(.fractionLength(0...1)))) kg·次")
        Text("容量只统计重量 × 次数模式中已完成的有效组；首次成绩作为基线。")
          .font(.caption).foregroundStyle(.secondary)
      }

      Section("本周突破") {
        if report.personalRecords.isEmpty {
          Text("本周还没有新的重量或容量纪录。每一次有效记录都会成为下次的参考。")
            .foregroundStyle(.secondary)
        } else {
          ForEach(report.personalRecords) { record in
            VStack(alignment: .leading, spacing: 5) {
              Label("\(record.exerciseName) · \(record.title)", systemImage: "trophy.fill")
                .font(.subheadline.bold())
              Text(
                "\(record.previousValue.formatted(.number.precision(.fractionLength(0...1)))) → \(record.value.formatted(.number.precision(.fractionLength(0...1)))) \(record.unit)"
              )
              .monospacedDigit()
            }
            .padding(.vertical, 4)
          }
        }
      }

      Section("饮食记录") {
        LabeledContent("有记录的日期", value: "\(report.nutritionDays) 天")
        if let calories = report.averageCalories, let protein = report.averageProtein {
          LabeledContent(
            "日均已记录热量", value: "\(calories.formatted(.number.precision(.fractionLength(0)))) kcal")
          LabeledContent(
            "日均已记录蛋白质", value: "\(protein.formatted(.number.precision(.fractionLength(0...1)))) g")
          Chart(days.filter(\.recorded)) { day in
            BarMark(x: .value("日期", day.date, unit: .day), y: .value("已记录热量", day.calories))
              .foregroundStyle(Color.accentColor)
              .accessibilityLabel(day.date.formatted(.dateTime.month().day()))
              .accessibilityValue(
                "\(day.calories.formatted(.number.precision(.fractionLength(0)))) 千卡")
          }
          .chartXScale(domain: report.interval.start...report.interval.end)
          .frame(height: 160)
        } else {
          Text("这一周尚无已填写营养的饮食记录。")
            .foregroundStyle(.secondary)
        }
        Text("平均值仅按填写过营养的 \(report.nutritionValueDays) 天计算。漏记日期不按零摄入处理；已记录数值不代表全天实际摄入。")
          .font(.caption).foregroundStyle(.secondary)
        if report.unknownFoodCount > 0 {
          Label("\(report.unknownFoodCount) 条食物未填写营养", systemImage: "info.circle")
            .font(.caption)
        }
      }

      Section("每日概览") {
        ForEach(days) { day in
          HStack {
            Text(day.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
              Text(
                day.recorded
                  ? "\(day.calories.formatted(.number.precision(.fractionLength(0)))) kcal"
                  : "营养未记录")
              Text("\(day.workouts) 次训练").font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .navigationTitle("每周回顾")
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
  let workouts: Int
  var id: Date { date }
}
