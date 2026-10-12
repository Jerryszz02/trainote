import SwiftData
import SwiftUI

struct TodayView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @AppStorage("onboarding.dismissed") private var onboardingDismissed = false
  @State private var currentDate = Date.now
  @State private var saveError: L10n.Message?
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
        legacyCurrent: NutritionGoalHistory.targets(from: goals.first))
        .map(TrendNutrition.displayed))
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 20) {
        header
        quickActions
        if let recoveryIntegration {
          TodayRecoveryCard(
            integration: recoveryIntegration, advice: trainingAdvice,
            hasRoutines: !routines.isEmpty,
            onOpenTemplates: onOpenTemplates, onOpenRecovery: onOpenRecovery,
            onOpenCheckIn: onOpenCheckIn)
        } else {
          recommendationCard
        }
        if !onboardingDismissed && workouts.isEmpty && foodEntries.isEmpty { gettingStarted }
        nutrientGrid
        routineShortcuts
        trainingSummary
        weeklyLink
        if let reportIntegration {
          NavigationLink {
            HealthReportsView(integration: reportIntegration)
          } label: {
            Label(L10n.text("core.basic.reports.and.history"), systemImage: "text.document")
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding().background(.background, in: RoundedRectangle(cornerRadius: 16))
          }
          .accessibilityIdentifier("today.analysisReports")
        }
      }
      .padding()
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle(L10n.text("core.today"))
    .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
          LibraryView()
        } label: {
          Label(L10n.text("core.library"), systemImage: "books.vertical")
        }
        .accessibilityIdentifier("today.library")
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button(L10n.text("core.settings"), systemImage: "gearshape") {
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
      L10n.text("core.could.not.save"), isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
    ) {
      Button(L10n.text("core.ok"), role: .cancel) { saveError = nil }
    } message: {
      Text(saveError?.text ?? L10n.text("core.please.try.again"))
    }
  }

  private var recommendationCard: some View {
    Button(action: routines.isEmpty ? onOpenTemplates : onOpenRecovery) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "lightbulb").font(.title2)
        VStack(alignment: .leading, spacing: 4) {
          Text(L10n.text("core.today.s.guidance")).font(.headline)
          Text(routines.isEmpty ? L10n.text("core.choose.a.routine.and.start.when.it.suits.you") : L10n.text("core.review.today.s.recovery.alongside.your.training.records.and.how.you.feel"))
            .font(.subheadline).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Image(systemName: "chevron.right").font(.caption)
      }
      .padding().background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("today.recommendation")
  }

  private var gettingStarted: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(L10n.text("core.start.with.a.workout.and.a.meal")).font(.headline)
        Spacer()
        Button(L10n.text("core.skip")) { onboardingDismissed = true }.font(.subheadline)
          .accessibilityIdentifier("onboarding.skip")
      }
      Text(L10n.text("core.save.exercises.and.foods.you.use.often.for.next.time.set.goals.whenever.you.like"))
        .font(.subheadline).foregroundStyle(.secondary)
      Button(L10n.text("core.create.a.routine"), systemImage: "list.bullet.rectangle", action: onOpenTemplates)
        .accessibilityIdentifier("today.createRoutine")
      Button(L10n.text("core.log.your.first.meal"), systemImage: "fork.knife", action: onLogFood)
      Button(L10n.text("core.set.daily.nutrition.goals"), systemImage: "target", action: onOpenSettings)
    }
    .padding()
    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
  }

  @ViewBuilder
  private var routineShortcuts: some View {
    if !routines.isEmpty && !workouts.contains(where: { $0.status == .inProgress }) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(L10n.text("core.favorite.routines")).font(.headline)
          Spacer()
          Button(L10n.text("core.manage.routines"), action: onOpenTemplates).font(.subheadline)
            .accessibilityIdentifier("today.manageTemplates")
        }
        ForEach(routines.prefix(3)) { routine in
          Button {
            guard routine.exercises.allSatisfy(\.hasValidDefaults) else {
              saveError = L10n.Message(resolving: { L10n.text("core.this.routine.has.invalid.values.edit.it.in.the.library.first") })
              return
            }
            let workout = RoutineFactory.workout(from: routine)
            modelContext.insert(workout)
            do {
              try modelContext.save()
              onStartWorkout()
            } catch {
              modelContext.rollback()
              saveError = L10n.Message(resolving: { L10n.text("core.could.not.start.the.workout.please.try.again" , String(describing: error.localizedDescription)) })
            }
          } label: {
            HStack {
              Image(systemName: "play.circle.fill")
              Text(routine.name).font(.subheadline.weight(.semibold))
              Spacer()
              Text(L10n.text("core.exercises", routine.exercises.count)).font(.caption).foregroundStyle(.secondary)
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
          Text(L10n.text("core.weekly.review.and.personal.records")).font(.headline)
          Text(L10n.text("core.see.changes.in.your.training.and.food.records")).font(.caption).foregroundStyle(.secondary)
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
      Text(currentDate.formatted(.dateTime.weekday(.wide).month().day().locale(L10n.locale)))
        .font(.title2.bold())
      Text(L10n.text("core.log.every.set.and.every.meal.today"))
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var nutrientGrid: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(L10n.text("core.nutrition.progress"))
          .font(.headline)
        Spacer()
        if goals.first == nil {
          Button(L10n.text("core.set.goals"), action: onOpenSettings)
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
        title: workouts.contains(where: { $0.status == .inProgress }) ? L10n.text("core.continue.workout") : L10n.text("core.start.workout"),
        subtitle: workouts.contains(where: { $0.status == .inProgress }) ? L10n.text("core.pick.up.where.you.left.off") : L10n.text("core.blank.workout.or.routine"),
        systemImage: "figure.strengthtraining.traditional",
        action: onStartWorkout
      )
      .accessibilityIdentifier("today.startWorkout")

      QuickActionButton(
        title: L10n.text("core.log.food"),
        subtitle: L10n.text("core.a.meal.or.food"),
        systemImage: "plus.circle.fill",
        action: onLogFood
      )
      .accessibilityIdentifier("today.logFood")
    }
  }

  private var trainingSummary: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L10n.text("core.today.s.training"))
        .font(.headline)

      if todayWorkouts.isEmpty {
        ContentUnavailableView(
          L10n.text("core.no.workouts.yet"),
          systemImage: "figure.walk",
          description: Text(L10n.text("core.start.a.workout.to.see.its.summary.here"))
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
                Text(L10n.text("core.exercises.81", workout.exercises.count, String(describing: workout.status.title)))
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

      Text(consumed.rounded(), format: .number.precision(.fractionLength(0)).locale(L10n.locale))
        .font(.title2.bold())
        .monospacedDigit()

      if target != nil {
        ProgressView(value: summary.progress(for: nutrient))
          .tint(remainingIsNegative ? .orange : .accentColor)
      }

      if let target, let remaining = summary.displayedRemaining(for: nutrient) {
        Text(
          remaining >= 0
            ? L10n.text("core.remaining" , String(describing: remaining.formatted(.number.precision(.fractionLength(0)).locale(L10n.locale))), String(describing: target.rounded().formatted(.number.precision(.fractionLength(0)).locale(L10n.locale))))
            : L10n.text("core.over" , String(describing: (-remaining).formatted(.number.precision(.fractionLength(0)).locale(L10n.locale))), String(describing: target.rounded().formatted(.number.precision(.fractionLength(0)).locale(L10n.locale))))
        )
        .font(.caption)
        .foregroundStyle(remaining >= 0 ? Color.secondary : Color.orange)
      } else {
        Text(L10n.text("core.no.goal.set.yet"))
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
        L10n.text("core.consumed.goal" , String(describing: nutrient.title), String(describing: consumed.rounded().formatted(.number.precision(.fractionLength(0)).locale(L10n.locale))), String(describing: nutrient.unit), String(describing: target.rounded().formatted(.number.precision(.fractionLength(0)).locale(L10n.locale))), String(describing: remaining >= 0 ? L10n.text("core.remaining.word") : L10n.text("core.over.word")), String(describing: abs(remaining).formatted(.number.precision(.fractionLength(0)).locale(L10n.locale))))
    }
    return
      L10n.text("core.consumed.no.goal.set.yet" , String(describing: nutrient.title), String(describing: consumed.rounded().formatted(.number.precision(.fractionLength(0)).locale(L10n.locale))), String(describing: nutrient.unit))
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
