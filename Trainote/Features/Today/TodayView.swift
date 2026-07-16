import SwiftData
import SwiftUI

private enum TodaySheet: String, Identifiable {
  case settings

  var id: String { rawValue }
}

struct TodayView: View {
  @Query(sort: \FoodLogEntry.loggedAt, order: .reverse)
  private var foodEntries: [FoodLogEntry]

  @Query(sort: \Workout.startedAt, order: .reverse)
  private var workouts: [Workout]

  @Query(sort: \NutritionGoal.updatedAt, order: .reverse)
  private var goals: [NutritionGoal]

  @State private var presentedSheet: TodaySheet?

  let onStartWorkout: () -> Void
  let onLogFood: () -> Void

  private var todayEntries: [FoodLogEntry] {
    foodEntries.filter { Calendar.current.isDateInToday($0.loggedAt) }
  }

  private var todayWorkouts: [Workout] {
    workouts.filter { Calendar.current.isDateInToday($0.startedAt) }
  }

  private var summary: DailyNutritionSummary {
    DailyNutritionSummary(entries: todayEntries, goal: goals.first)
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 20) {
        header
        nutrientGrid
        quickActions
        trainingSummary
      }
      .padding()
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("今日")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("设置", systemImage: "gearshape") {
          presentedSheet = .settings
        }
        .accessibilityIdentifier("today.settings")
      }
    }
    .sheet(item: $presentedSheet) { sheet in
      switch sheet {
      case .settings:
        SettingsView()
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
        .font(.title2.bold())
      Text("把今天的每一组和每一餐记下来。")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var nutrientGrid: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("营养进度")
          .font(.headline)
        Spacer()
        if goals.first == nil {
          Button("设置目标") { presentedSheet = .settings }
            .font(.subheadline)
        }
      }

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        ForEach(NutrientKind.allCases) { nutrient in
          NutrientProgressCard(nutrient: nutrient, summary: summary)
        }
      }
    }
  }

  private var quickActions: some View {
    HStack(spacing: 12) {
      QuickActionButton(
        title: "开始训练",
        subtitle: "空白或 routine",
        systemImage: "figure.strengthtraining.traditional",
        action: onStartWorkout
      )
      .accessibilityIdentifier("today.startWorkout")

      QuickActionButton(
        title: "记录饮食",
        subtitle: "一餐或食物",
        systemImage: "plus.circle.fill",
        action: onLogFood
      )
      .accessibilityIdentifier("today.logFood")
    }
  }

  private var trainingSummary: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("今日训练")
        .font(.headline)

      if todayWorkouts.isEmpty {
        ContentUnavailableView(
          "还没有训练记录",
          systemImage: "figure.walk",
          description: Text("开始一场训练后，摘要会出现在这里。")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
      } else {
        ForEach(todayWorkouts.prefix(3)) { workout in
          HStack {
            Image(systemName: workout.status == .completed ? "checkmark.circle.fill" : "clock.fill")
              .foregroundStyle(workout.status == .completed ? .green : .orange)
              .accessibilityHidden(true)
            VStack(alignment: .leading) {
              Text(workout.title)
                .font(.subheadline.weight(.semibold))
              Text("\(workout.exercises.count) 个动作 · \(workout.status.title)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(workout.startedAt, style: .time)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding()
          .background(.background, in: RoundedRectangle(cornerRadius: 14))
        }
      }
    }
  }
}

private struct NutrientProgressCard: View {
  let nutrient: NutrientKind
  let summary: DailyNutritionSummary

  private var consumed: Double { summary.consumed.value(for: nutrient) }
  private var target: Double? { summary.goal?.value(for: nutrient) }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(nutrient.title)
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text(nutrient.unit)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text(consumed, format: .number.precision(.fractionLength(0)))
        .font(.title2.bold())
        .monospacedDigit()

      ProgressView(value: summary.progress(for: nutrient))
        .tint(remainingIsNegative ? .orange : .accentColor)

      if let target, let remaining = summary.remaining(for: nutrient) {
        Text(
          remaining >= 0
            ? "剩余 \(remaining, format: .number.precision(.fractionLength(0))) / \(target, format: .number.precision(.fractionLength(0)))"
            : "超出 \((-remaining), format: .number.precision(.fractionLength(0))) / \(target, format: .number.precision(.fractionLength(0)))"
        )
        .font(.caption)
        .foregroundStyle(remaining >= 0 ? Color.secondary : Color.orange)
      } else {
        Text("尚未设置目标")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding()
    .background(.background, in: RoundedRectangle(cornerRadius: 16))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityText)
  }

  private var remainingIsNegative: Bool {
    (summary.remaining(for: nutrient) ?? 0) < 0
  }

  private var accessibilityText: String {
    if let target, let remaining = summary.remaining(for: nutrient) {
      return
        "\(nutrient.title)，已摄入 \(Int(consumed)) \(nutrient.unit)，目标 \(Int(target))，\(remaining >= 0 ? "剩余" : "超出") \(Int(abs(remaining)))"
    }
    return "\(nutrient.title)，已摄入 \(Int(consumed)) \(nutrient.unit)，尚未设置目标"
  }
}

private struct QuickActionButton: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 10) {
        Image(systemName: systemImage)
          .font(.title2)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.headline)
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
      .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
    .buttonStyle(.plain)
  }
}
