import SwiftData
import SwiftUI

private enum TodaySheet: String, Identifiable {
  case settings

  var id: String { rawValue }
}

struct TodayView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @AppStorage("onboarding.dismissed") private var onboardingDismissed = false
  @State private var currentDate = Date.now
  @State private var saveError: String?
  @Query(sort: \Routine.updatedAt, order: .reverse) private var routines: [Routine]

  @Query(sort: \FoodLogEntry.loggedAt, order: .reverse)
  private var foodEntries: [FoodLogEntry]

  @Query(sort: \Workout.startedAt, order: .reverse)
  private var workouts: [Workout]

  @Query(sort: \NutritionGoal.updatedAt, order: .reverse)
  private var goals: [NutritionGoal]

  @State private var presentedSheet: TodaySheet?

  let onStartWorkout: () -> Void
  let onLogFood: () -> Void
  var onOpenTemplates: () -> Void = {}

  private var todayEntries: [FoodLogEntry] {
    foodEntries.filter { Calendar.current.isDate($0.loggedAt, inSameDayAs: currentDate) }
  }

  private var todayWorkouts: [Workout] {
    workouts.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: currentDate) }
  }

  private var summary: DailyNutritionSummary {
    DailyNutritionSummary(entries: todayEntries, goal: goals.first)
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 20) {
        header
        quickActions
        if !onboardingDismissed && workouts.isEmpty && foodEntries.isEmpty { gettingStarted }
        nutrientGrid
        routineShortcuts
        trainingSummary
        weeklyLink
      }
      .padding()
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("今日")
    .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("设置", systemImage: "gearshape") {
          presentedSheet = .settings
        }
        .accessibilityIdentifier("today.settings")
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { currentDate = .now }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
    ) { _ in currentDate = .now }
    .alert(
      "未能保存", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
    ) {
      Button("知道了", role: .cancel) { saveError = nil }
    } message: {
      Text(saveError ?? "请重试。")
    }
    .sheet(item: $presentedSheet) { sheet in
      switch sheet {
      case .settings:
        SettingsView()
      }
    }
  }

  private var gettingStarted: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("从一套训练和一餐开始").font(.headline)
        Spacer()
        Button("跳过") { onboardingDismissed = true }.font(.subheadline)
          .accessibilityIdentifier("onboarding.skip")
      }
      Text("先保存常做的动作和常吃的食物，下次直接复用。目标可以随时设置。")
        .font(.subheadline).foregroundStyle(.secondary)
      Button("建立训练模板", systemImage: "list.bullet.rectangle", action: onOpenTemplates)
        .accessibilityIdentifier("today.createRoutine")
      Button("记录第一餐", systemImage: "fork.knife", action: onLogFood)
      Button("设置每日营养目标", systemImage: "target") { presentedSheet = .settings }
    }
    .padding()
    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
  }

  @ViewBuilder
  private var routineShortcuts: some View {
    if !routines.isEmpty && !workouts.contains(where: { $0.status == .inProgress }) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("常用训练模板").font(.headline)
          Spacer()
          Button("管理", action: onOpenTemplates).font(.subheadline)
        }
        ForEach(routines.prefix(3)) { routine in
          Button {
            guard routine.exercises.allSatisfy(\.hasValidDefaults) else {
              saveError = "模板包含无效参数，请先在资料库中编辑修正。"
              return
            }
            let workout = RoutineFactory.workout(from: routine)
            modelContext.insert(workout)
            do {
              try modelContext.save()
              onStartWorkout()
            } catch {
              modelContext.rollback()
              saveError = "训练未能开始，请重试。\(error.localizedDescription)"
            }
          } label: {
            HStack {
              Image(systemName: "play.circle.fill")
              Text(routine.name).font(.subheadline.weight(.semibold))
              Spacer()
              Text("\(routine.exercises.count) 个动作").font(.caption).foregroundStyle(.secondary)
            }
            .padding().background(.background, in: RoundedRectangle(cornerRadius: 14))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("today.routine.\(routine.id.uuidString)")
        }
      }
    }
  }

  private var weeklyLink: some View {
    NavigationLink {
      WeeklyReportView()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "chart.xyaxis.line").font(.title2)
        VStack(alignment: .leading, spacing: 4) {
          Text("每周回顾与 PR").font(.headline)
          Text("看见训练积累和饮食记录的变化").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "chevron.right").font(.caption)
      }
      .padding().background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("today.weeklyReport")
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(currentDate.formatted(.dateTime.weekday(.wide).month().day()))
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

      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
        spacing: 12
      ) {
        ForEach(NutrientKind.allCases) { nutrient in
          NutrientProgressCard(nutrient: nutrient, summary: summary)
        }
      }
    }
  }

  private var quickActions: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
    return layout {
      QuickActionButton(
        title: workouts.contains(where: { $0.status == .inProgress }) ? "继续训练" : "开始训练",
        subtitle: workouts.contains(where: { $0.status == .inProgress }) ? "接着完成这一场" : "空白或训练模板",
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
          NavigationLink {
            if workout.status == .inProgress {
              ActiveWorkoutView(workout: workout)
            } else {
              WorkoutDetailView(workout: workout)
            }
          } label: {
            HStack {
              Image(
                systemName: workout.status == .completed ? "checkmark.circle.fill" : "clock.fill"
              )
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
          .buttonStyle(.plain)
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
        "\(nutrient.title)，已摄入 \(consumed.formatted(.number.precision(.fractionLength(0)))) \(nutrient.unit)，目标 \(target.formatted(.number.precision(.fractionLength(0))))，\(remaining >= 0 ? "剩余" : "超出") \(abs(remaining).formatted(.number.precision(.fractionLength(0))))"
    }
    return
      "\(nutrient.title)，已摄入 \(consumed.formatted(.number.precision(.fractionLength(0)))) \(nutrient.unit)，尚未设置目标"
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
