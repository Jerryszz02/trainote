import SwiftData
import SwiftUI

struct TodayView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var currentDate = Date.now
  @State private var saveError: String?
  @Query(sort: \Routine.updatedAt, order: .reverse) private var routines: [Routine]

  @Query(sort: \FoodLogEntry.loggedAt, order: .reverse)
  private var foodEntries: [FoodLogEntry]

  @Query(sort: \Workout.startedAt, order: .reverse)
  private var workouts: [Workout]

  @Query(sort: \NutritionGoal.updatedAt, order: .reverse)
  private var goals: [NutritionGoal]
  @Query(sort: \NutritionGoalRevision.effectiveAt, order: .reverse)
  private var goalRevisions: [NutritionGoalRevision]

  let onStartWorkout: () -> Void
  let onLogFood: () -> Void
  var onOpenNutrition: () -> Void = {}
  var onOpenTemplates: () -> Void = {}
  var onOpenRecovery: () -> Void = {}
  var onOpenSettings: () -> Void = {}
  var onOpenCheckIn: (CheckInValue, @escaping () -> Void) -> Void = { _, _ in }
  var recoveryIntegration: HealthRecoveryIntegration? = nil
  var trainingAdvice: TrainingAdviceController? = nil
  var reportIntegration: HealthReportIntegration? = nil

  private var todayEntries: [FoodLogEntry] {
    foodEntries.filter { Calendar.current.isDate($0.loggedAt, inSameDayAs: currentDate) }
  }

  private var todayWorkouts: [Workout] {
    workouts.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: currentDate) }
  }

  private var summary: DailyNutritionSummary {
    DailyNutritionSummary(
      entries: todayEntries,
      historicalTargets: NutritionGoalHistory.targets(
        on: currentDate, history: goalRevisions.map(\.value),
        legacyCurrent: NutritionGoalHistory.targets(from: goals.first)
      )
      .map(TrendNutrition.displayed))
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 20) {
        header
        quickActions
        Text("今天已记录").font(.headline)
        trainingSummary
        Button(action: onOpenNutrition) {
          HStack {
            Label("饮食 · \(todayEntries.count) 条记录", systemImage: "fork.knife")
            Spacer()
            Image(systemName: "chevron.right").accessibilityHidden(true)
          }
        }
        .accessibilityIdentifier("today.nutritionSummary")
        nutrientGrid
        routineShortcuts
      }
      .padding()
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("今日")
    .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
          LibraryView()
        } label: {
          Label("资料库", systemImage: "books.vertical")
        }
        .accessibilityIdentifier("today.library")
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button("设置", systemImage: "gearshape") {
          onOpenSettings()
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
  }

  @ViewBuilder
  private var routineShortcuts: some View {
    if !routines.isEmpty && !workouts.contains(where: { $0.status == .inProgress }) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("常用训练模板").font(.headline)
          Spacer()
          Button("管理模板", action: onOpenTemplates).font(.subheadline)
            .accessibilityIdentifier("today.manageTemplates")
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

  private var header: some View {
    Text(currentDate.formatted(.dateTime.weekday(.wide).month().day()))
      .font(.title2.bold())
  }

  private var nutrientGrid: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("营养进度")
          .font(.headline)
        Spacer()
        if goals.first == nil {
          Button("设置目标", action: onOpenSettings)
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
    VStack(alignment: .leading, spacing: 12) {
      Button(action: onStartWorkout) {
        Label(
          workouts.contains(where: { $0.status == .inProgress }) ? "继续训练" : "开始训练",
          systemImage: "figure.strengthtraining.traditional"
        )
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.borderedProminent)
      .accessibilityIdentifier("today.startWorkout")
      if let active = workouts.first(where: { $0.status == .inProgress }) {
        Text("\(active.title) · 已完成 \(WorkoutInsights.completedSets(in: active)) 组")
          .font(.subheadline).foregroundStyle(.secondary)
          .accessibilityIdentifier("today.activeProgress")
      }
      Button(action: onLogFood) {
        Label("记录饮食", systemImage: "plus.circle")
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("today.logFood")
    }
  }

  private var trainingSummary: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("今日训练")
        .font(.headline)

      if todayWorkouts.isEmpty {
        Label("尚未记录训练", systemImage: "figure.walk")
          .foregroundStyle(.secondary)
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

      Text(consumed.rounded(), format: .number.precision(.fractionLength(0)))
        .font(.title2.bold())
        .monospacedDigit()

      if target != nil {
        ProgressView(value: summary.progress(for: nutrient))
          .tint(remainingIsNegative ? .orange : .accentColor)
      }

      if let target, let remaining = summary.displayedRemaining(for: nutrient) {
        Text(
          remaining >= 0
            ? "剩余 \(remaining, format: .number.precision(.fractionLength(0))) / \(target.rounded(), format: .number.precision(.fractionLength(0)))"
            : "超出 \((-remaining), format: .number.precision(.fractionLength(0))) / \(target.rounded(), format: .number.precision(.fractionLength(0)))"
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
    .accessibilityIdentifier("today.nutrient.\(nutrient.rawValue)")
  }

  private var remainingIsNegative: Bool {
    (summary.displayedRemaining(for: nutrient) ?? 0) < 0
  }

  private var accessibilityText: String {
    if let target, let remaining = summary.displayedRemaining(for: nutrient) {
      return
        "\(nutrient.title)，已摄入 \(consumed.rounded().formatted(.number.precision(.fractionLength(0)))) \(nutrient.unit)，目标 \(target.rounded().formatted(.number.precision(.fractionLength(0))))，\(remaining >= 0 ? "剩余" : "超出") \(abs(remaining).formatted(.number.precision(.fractionLength(0))))"
    }
    return
      "\(nutrient.title)，已摄入 \(consumed.rounded().formatted(.number.precision(.fractionLength(0)))) \(nutrient.unit)，尚未设置目标"
  }
}
