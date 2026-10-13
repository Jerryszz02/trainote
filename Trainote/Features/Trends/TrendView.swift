import Charts
import SwiftUI

/// Embed in F's NavigationStack. No app-root or Settings ownership is assumed here.
struct TrendView: View {
  @State private var model: TrendViewModel
  var onOpenManualGoal: (() -> Void)?
  var onOpenHelp: (() -> Void)?
  @State private var rangeDays = 28
  @State private var showProfile = false
  @State private var showWeight = false
  @State private var showAutomaticConfirmation = false
  @State private var showEmptyDietConfirmation = false
  @State private var dietDate = Date.now

  init(
    model: TrendViewModel, onOpenManualGoal: (() -> Void)? = nil,
    onOpenHelp: (() -> Void)? = nil
  ) {
    _model = State(initialValue: model)
    self.onOpenManualGoal = onOpenManualGoal
    self.onOpenHelp = onOpenHelp
  }
  private var start: Date {
    rangeDays == 0 ? .distantPast : model.calendar.adding(days: -rangeDays, to: model.now())
  }
  private var points: [TrendPoint] { model.result?.points.filter { $0.date >= start } ?? [] }
  private var weights: [WeightSample] {
    model.input?.weights.filter {
      $0.measuredAt >= start && $0.measuredAt <= model.now() && $0.kilograms.isFinite
    } ?? []
  }
  private var weightDomain: ClosedRange<Double> {
    let values = weights.map(\.kilograms)
    return ((values.min() ?? 69) - 0.5)...((values.max() ?? 71) + 0.5)
  }
  var body: some View {
    List {
      overview
      weightChart
      dietSection
      goalSection
      historySection
      Section {
        Button(L10n.text("health.trendview.body.details.and.goal.direction.ad25de")) { showProfile = true }
          .accessibilityIdentifier("trend.profile")
        if let onOpenManualGoal { Button(L10n.text("health.trendview.edit.manual.nutrition.targets.9bc7a5"), action: onOpenManualGoal) }
        if let onOpenHelp { Button(L10n.text("health.trendview.methods.and.data.use.df2501"), action: onOpenHelp) }
      }
    }
    .navigationTitle(L10n.text("health.trendview.trend.analysis.cc7a87"))
    .accessibilityIdentifier("trend.screen")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(L10n.text("health.trendview.record.weight.158001"), systemImage: "plus") { showWeight = true }
          .accessibilityIdentifier("trend.addWeight")
      }
    }
    .task {
      dietDate = model.now()
      model.reload()
    }
    .refreshable { model.reload() }
    .sheet(isPresented: $showProfile) { TrendProfileForm(model: model) }
    .sheet(isPresented: $showWeight) { TrendWeightForm(model: model) }
    .alert(
      L10n.text("health.trendview.could.not.complete.a49f84"),
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: {
          if !$0 { model.errorMessage = nil }
        })
    ) {
      Button(L10n.text("health.trendview.ok.27e4fe"), role: .cancel) { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
    .confirmationDialog(
      L10n.text("health.trendview.enable.weekly.automatic.adoption.918ef7"), isPresented: $showAutomaticConfirmation, titleVisibility: .visible
    ) {
      Button(L10n.text("health.trendview.enable.automatic.adoption.193285")) {
        model.setMode(.automatic)
        model.reload()
      }
      Button(L10n.text("health.trendview.cancel.4d0b46"), role: .cancel) {}
    } message: {
      Text(L10n.text("health.trendview.you.adopt.the.initial.targets.first.b01f1e"))
    }
    .confirmationDialog(
      L10n.text("health.trendview.no.food.records.for.this.day.9fc2f9"), isPresented: $showEmptyDietConfirmation, titleVisibility: .visible
    ) {
      Button(L10n.text("health.trendview.confirm.no.intake.and.mark.complete.cf8066")) { model.confirmDiet(on: dietDate) }
      Button(L10n.text("health.trendview.keep.adding.records.29d868"), role: .cancel) {}
    } message: {
      Text(L10n.text("health.trendview.missing.records.are.not.treated.as.13c1c7"))
    }
  }
  private var overview: some View {
    Section {
      if let value = model.result?.points.last(where: { $0.smoothedKilograms != nil })?
        .smoothedKilograms
      {
        LabeledContent(L10n.text("health.trendview.trend.weight.dfd7ed"), value: String(format: "%.1f kg", locale: L10n.locale, value))
      } else {
        Text(L10n.text("health.trendview.record.weight.to.start.building.a.2b359d")).foregroundStyle(.secondary)
      }
      LabeledContent(L10n.text("health.trendview.goal.direction.4a9679"), value: model.input?.profile?.goalDirection?.trendTitle ?? L10n.text("health.trendview.not.set.4c3ba6"))
      if model.needsProfileCompletion {
        Button(L10n.text("health.trendview.complete.profile.2707e3")) { showProfile = true }
          .accessibilityIdentifier("trend.completeProfile")
      }
      if let rate = model.result?.weeklyChangePercent {
        LabeledContent(L10n.text("health.trendview.rate.over.the.last.21.days.574730"), value: String(format: L10n.text("health.trendview.2f.week.67786a"), locale: L10n.locale, rate))
      }
      if let next = model.nextReview, next > model.now() {
        LabeledContent(L10n.text("health.trendview.next.review.c0ddc0"), value: next.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L10n.locale)))
      }
      if let hold = model.result?.holdReason {
        Text(hold.trendMessage).foregroundStyle(.secondary).accessibilityIdentifier("trend.hold")
      }
      if let input = model.input, TrendHistory.needsBaselineRebuild(input) {
        Text(L10n.text("health.trendview.body.details.updated.after.7.days.92cef0"))
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
  }
  private var weightChart: some View {
    Section(L10n.text("health.trendview.weight.kg.157e4a")) {
      Picker(L10n.text("health.trendview.time.range.2be904"), selection: $rangeDays) {
        Text(L10n.text("health.trendview.4.weeks.e9fcd6")).tag(28)
        Text(L10n.text("health.trendview.12.weeks.4945ee")).tag(84)
        Text(L10n.text("health.trendview.all.778fc8")).tag(0)
      }.pickerStyle(.segmented)
      if points.isEmpty {
        ContentUnavailableView(
          L10n.text("health.trendview.no.weight.records.yet.479161"), systemImage: "chart.xyaxis.line",
          description: Text(L10n.text("health.trendview.record.weight.manually.or.connect.apple.4ed497")))
      } else {
        Chart {
          ForEach(weights) { sample in
            PointMark(x: .value(L10n.text("health.trendview.date.b6fed9"), sample.measuredAt), y: .value(L10n.text("health.trendview.weight.319359"), sample.kilograms))
              .foregroundStyle(.secondary.opacity(0.5)).symbolSize(18)
              .accessibilityLabel(sample.source.kind == .manual ? L10n.text("health.trendview.manual.weight.3a6160") : L10n.text("health.trendview.apple.health.weight.59a2eb"))
              .accessibilityValue(String(format: L10n.text("health.trendview.1f.kilograms.e871a8"), locale: L10n.locale, sample.kilograms))
          }
          ForEach(Array(points.enumerated()), id: \.offset) { _, point in
            if let smooth = point.smoothedKilograms {
              LineMark(x: .value(L10n.text("health.trendview.date.b6fed9"), point.date), y: .value(L10n.text("health.trendview.smoothed.trend.99ca06"), smooth))
                .foregroundStyle(Color.accentColor)
            }
          }
        }
        .chartYScale(domain: weightDomain)
        .frame(height: 200)
        .accessibilityIdentifier("trend.weightChart")
        Text(L10n.text("health.trendview.dots.are.source.readings.and.the.365667"))
          .font(.caption).foregroundStyle(.secondary)
      }
      NavigationLink(L10n.text("health.trendview.weight.records.and.sources.4351f2")) { TrendWeightRecordsView(model: model) }
    }
  }
  private var dietSection: some View {
    Section(L10n.text("health.trendview.intake.completeness.61c19d")) {
      if let value = model.result?.facts.first(where: { $0.metric == "diet.completeDays" })?.value {
        LabeledContent(L10n.text("health.trendview.14.days.through.yesterday.2a2411"), value: L10n.text("health.trendview.14.days.confirmed.7090fb", String(Int(value))))
      }
      DatePicker(L10n.text("health.trendview.confirmation.date.b4aa5a"), selection: $dietDate, in: ...model.now(), displayedComponents: .date)
      let selected = model.input?.nutrition.first { $0.localDate == model.calendar.key(dietDate) }
      if selected?.isComplete == true {
        Label(L10n.text("health.trendview.selected.day.confirmed.complete.f794cf"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
      } else {
        Button(L10n.text("health.trendview.food.records.for.this.day.are.add823")) {
          if selected?.logIDs.isEmpty != false {
            showEmptyDietConfirmation = true
          } else {
            model.confirmDiet(on: dietDate)
          }
        }.accessibilityIdentifier("trend.confirmDiet")
        Text(L10n.text("health.trendview.confirm.again.after.editing.food.records.1b445b"))
          .font(.caption).foregroundStyle(.secondary)
      }
      if let totals = selected?.totals { targetRows(totals, prefix: L10n.text("health.trendview.recorded.d94731")) }
      let nutrition =
        model.input?.nutrition.filter {
          model.calendar.date($0.localDate).map { $0 >= start } == true
        } ?? []
      if !nutrition.isEmpty {
        Chart(Array(nutrition.enumerated()), id: \.offset) { _, day in
          if let date = model.calendar.date(day.localDate) {
            BarMark(x: .value(L10n.text("health.trendview.date.b6fed9"), date), y: .value(L10n.text("health.trendview.recorded.calories.27ef14"), day.totals.calories))
              .foregroundStyle(day.isComplete ? Color.accentColor : Color.secondary.opacity(0.4))
          }
        }
        .chartXAxis {
          AxisMarks(values: .automatic(desiredCount: 3)) { _ in
            AxisGridLine()
            AxisTick()
            AxisValueLabel(format: .dateTime.month().day().locale(L10n.locale))
          }
        }
        .frame(height: 120)
        Text(L10n.text("health.trendview.calories.kcal.pale.bars.are.unconfirmed.ea2a67"))
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  private var goalSection: some View {
    Section(L10n.text("health.trendview.nutrition.targets.144c16")) {
      Picker(
        L10n.text("health.trendview.target.mode.09c02b"),
        selection: Binding(
          get: { model.input?.preferences.goalMode ?? .manual },
          set: {
            if $0 == .automatic { showAutomaticConfirmation = true } else { model.setMode($0) }
          })
      ) {
        Text(L10n.text("health.trendview.manual.2a4a4d")).tag(GoalMode.manual)
        Text(L10n.text("health.trendview.suggest.then.adopt.da8750")).tag(GoalMode.suggested)
        Text(L10n.text("health.trendview.adopt.automatically.each.week.4096e5")).tag(GoalMode.automatic)
      }.accessibilityIdentifier("trend.goalMode")
      if let current = model.input?.currentManualTargets {
        targetRows(current, prefix: L10n.text("health.trendview.current.25e74d"))
        if let latest = model.input.flatMap({
          TrendHistory.effective(at: $0.asOf, history: $0.goalHistory)
        }) {
          Text(L10n.text("health.trendview.effective.ae28ab", String(latest.effectiveAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L10n.locale)))))
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      if let proposal = model.result?.proposal {
        targetRows(proposal.targets, prefix: L10n.text("health.trendview.suggested.c5134e"))
        if let previous = proposal.previousTargets {
          let adjustment =
            TrendNutrition.displayed(proposal.targets).calories
            - TrendNutrition.displayed(previous).calories
          Text(String(format: L10n.text("health.trendview.calorie.adjustment.0f.kcal.a345d5"), locale: L10n.locale, adjustment))
        } else {
          Text(L10n.text("health.trendview.initial.targets.based.on.body.details.6b2ac0"))
        }
        DisclosureGroup(L10n.text("health.trendview.suggestion.evidence.a8c05c")) {
          ForEach(model.result?.facts.filter { proposal.reasonFactIDs.contains($0.id) } ?? []) {
            fact in
            if let value = fact.value {
              LabeledContent(
                fact.trendTitle, value: String(format: "%.1f %@", locale: L10n.locale, value, fact.unit.trendTitle))
            }
          }
        }
        let rebuilding = model.input.map { TrendHistory.needsBaselineRebuild($0) } ?? false
        if rebuilding {
          Text(L10n.text("health.trendview.this.is.an.initial.estimate.for.fa9fb5"))
            .font(.footnote).foregroundStyle(.secondary)
        }
        Button(rebuilding ? L10n.text("health.trendview.adopt.new.initial.targets.c49356") : L10n.text("health.trendview.adopt.suggestion.8b65eb")) { model.adopt(proposal.id) }
          .disabled(!model.canApplyGoals).accessibilityIdentifier("trend.adopt")
        Button(L10n.text("health.trendview.skip.for.now.review.in.7.592da6")) {
          model.pause(until: model.calendar.adding(days: 7, to: model.now()))
        }
      }
      if model.input?.preferences.pausedUntil.map({ $0 > model.now() }) == true {
        Button(L10n.text("health.trendview.resume.suggestion.reviews.dfd8dc")) { model.pause(until: nil) }.accessibilityIdentifier("trend.resume")
      } else {
        Button(L10n.text("health.trendview.pause.adjustments.for.7.days.ed13ce")) { model.pause(until: model.calendar.adding(days: 7, to: model.now())) }
          .accessibilityIdentifier("trend.pause")
      }
    }
  }
  private var historySection: some View {
    Section(L10n.text("health.trendview.target.history.a2fc48")) {
      let history = TrendHistory.ordered(model.input?.goalHistory ?? []).reversed()
      if history.isEmpty {
        Text(L10n.text("health.trendview.history.is.preserved.after.adoption.or.db37a7"))
          .foregroundStyle(.secondary)
      }
      ForEach(Array(history)) { revision in
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text(revision.effectiveAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L10n.locale)))
            Spacer()
            Text(revision.reversesRevisionID == nil ? revision.origin.trendTitle : L10n.text("health.trendview.restored.by.undo.a83748"))
              .font(.caption).foregroundStyle(.secondary)
          }
          targetRows(revision.targets, prefix: "")
          if TrendHistory.isReversed(revision, history: model.input?.goalHistory ?? []) {
            Text(L10n.text("health.trendview.undone.61063b")).font(.caption).foregroundStyle(.secondary)
          } else if let input = model.input, TrendGoalWorkflow.canUndo(revision.id, input: input) {
            Button(L10n.text("health.trendview.undo.and.pause.for.7.days.d32b67")) { model.undo(revision.id) }
              .disabled(!model.canApplyGoals).accessibilityIdentifier("trend.undo")
            Text(L10n.text("health.trendview.restore.the.previous.targets.resume.reviews.51d993"))
              .font(.caption).foregroundStyle(.secondary)
          } else if history.count == 1 && revision.origin != .manual {
            Text(L10n.text("health.trendview.this.is.the.first.target.with.b56593"))
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
  }
  private func targetRows(_ targets: NutritionTargets, prefix: String) -> some View {
    let shown = TrendNutrition.displayed(targets)
    return VStack(alignment: .leading, spacing: 4) {
      Text("\(prefix) \(Int(shown.calories)) kcal").font(.headline).monospacedDigit()
      Text(
        L10n.text("health.trendview.carbs.g.protein.g.fat.g.5af02d", String(Int(shown.carbohydrates)), String(Int(shown.protein)), String(Int(shown.fat)))
      )
      .font(.subheadline).foregroundStyle(.secondary)
    }.accessibilityElement(children: .combine)
  }
}

extension GoalDirection {
  var trendTitle: String { self == .maintain ? L10n.text("health.trendview.maintain.06fbde") : self == .lose ? L10n.text("health.trendview.lose.fat.170fab") : L10n.text("health.trendview.gain.muscle.5ea5b9") }
}
extension GoalRevisionOrigin {
  var trendTitle: String { self == .manual ? L10n.text("health.trendview.manual.2a4a4d") : self == .suggested ? L10n.text("health.trendview.suggestion.adopted.bb7a31") : L10n.text("health.trendview.automatic.adoption.996751") }
}
extension TrendHoldReason {
  var trendMessage: String {
    switch self {
    case .missingProfile: return L10n.text("health.trendview.add.body.details.to.generate.initial.1fb59a")
    case .insufficientWeights: return L10n.text("health.trendview.not.enough.weight.records.at.least.30cdcc")
    case .incompleteDiet: return L10n.text("health.trendview.at.least.12.of.the.last.a9e4fd")
    case .baselineBuilding: return L10n.text("health.trendview.building.a.baseline.observe.for.at.a42812")
    case .manualMode: return L10n.text("health.trendview.using.manual.targets.you.can.choose.bcdb3c")
    case .paused: return L10n.text("health.trendview.adjustments.paused.current.targets.are.kept.74bb86")
    case .safetyBoundary: return L10n.text("health.trendview.your.current.body.details.or.nutrition.533285")
    case .requiresReview: return L10n.text("health.trendview.review.unusual.weights.body.details.or.b59daa")
    case .unchanged: return L10n.text("health.trendview.recent.changes.are.within.the.goal.5caf24")
    case .readFailed: return L10n.text("health.trendview.weight.could.not.be.read.retry.89a8b3")
    }
  }
}
extension MetricFact {
  var trendTitle: String {
    switch metric {
    case "weight.smoothed": return L10n.text("health.trendview.trend.weight.dfd7ed")
    case "energy.initialEstimate": return L10n.text("health.trendview.formula.energy.reference.26695c")
    case "weight.targetWeeklyChangePercent": return L10n.text("health.trendview.target.rate.d9e3a8")
    case "weight.weeklyChangePercent": return L10n.text("health.trendview.recent.rate.29b7d0")
    case "diet.completeDays": return L10n.text("health.trendview.complete.food.days.d5dad7")
    case "diet.targetDifferencePercent": return L10n.text("health.trendview.intake.difference.from.historical.targets.6a6733")
    default: return metric
    }
  }
}
extension MetricUnit {
  var trendTitle: String {
    switch self {
    case .kilograms: return "kg"
    case .kilocalories: return "kcal"
    case .percentPerWeek: return L10n.text("health.trendview.week.76712a")
    case .percent: return "%"
    case .count: return L10n.text("health.trendview.days.c3304d")
    default: return rawValue
    }
  }
}
