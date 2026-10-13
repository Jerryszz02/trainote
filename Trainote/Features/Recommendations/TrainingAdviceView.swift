import SwiftUI

/// A plan is chosen for this review only; the app never infers a recurring plan.
struct TrainingAdviceView: View {
  @Environment(\.scenePhase) private var scenePhase
  let controller: TrainingAdviceController
  let onStartWorkout: (Workout) -> Void
  var onOpenNutrition: (() -> Void)? = nil
  var onOpenRecovery: (() -> Void)? = nil

  @State private var pendingActionID: String?
  @State private var parameterActionID: String?
  @State private var parameterValues: [String: Double] = [:]
  @State private var actionError: String?
  @State private var checkInDraft: CheckInValue?

  var body: some View {
    List {
      if let activeWorkout = controller.activeWorkout {
        Section(L10n.text("health.trainingadviceview.workout.in.progress.9b5f5a")) {
          Text(L10n.text("health.trainingadviceview.you.already.have.a.workout.in.63ffd7"))
            .foregroundStyle(.secondary)
          Button(L10n.text("health.trainingadviceview.continue.current.workout.df1345")) { onStartWorkout(activeWorkout) }
            .accessibilityIdentifier("advice.continueWorkout")
        }
      }
      Section(L10n.text("health.trainingadviceview.this.workout.3658d6")) {
        Picker(
          L10n.text("health.trainingadviceview.choose.a.template.860cb3"),
          selection: Binding(
            get: { controller.selectedRoutineID },
            set: { controller.selectedRoutineID = $0 }
          )
        ) {
          Text(L10n.text("health.trainingadviceview.not.selected.22c7d7")).tag(Optional<UUID>.none)
          ForEach(controller.routines) { routine in
            Text(routine.name).tag(Optional(routine.id))
          }
        }
        .accessibilityIdentifier("advice.selectedRoutine")
        Text(L10n.text("health.trainingadviceview.this.selects.a.template.for.this.dc4235"))
          .font(.caption).foregroundStyle(.secondary)
        if let selected = controller.selectedRoutineID {
          ForEach(controller.routines.filter { $0.id != selected }) { routine in
            Toggle(
              L10n.text("health.trainingadviceview.alternative.624cdd", String(routine.name)),
              isOn: Binding(
                get: { controller.alternativeRoutineIDs.contains(routine.id) },
                set: { value in
                  if value {
                    controller.alternativeRoutineIDs.insert(routine.id)
                  } else {
                    controller.alternativeRoutineIDs.remove(routine.id)
                  }
                })
            )
            .accessibilityIdentifier("advice.alternative.\(routine.id.uuidString)")
          }
        }
      }
      Section(L10n.text("health.trainingadviceview.training.days.optional.0e438b")) {
        if controller.availableWeekdays == nil {
          Button(L10n.text("health.trainingadviceview.add.training.days.a27ac3")) { controller.availableWeekdays = [] }
            .accessibilityIdentifier("advice.schedule.start")
        } else {
          ForEach(1...7, id: \.self) { day in
            Toggle(
              weekdayName(day),
              isOn: Binding(
                get: { controller.availableWeekdays?.contains(day) == true },
                set: { value in
                  var days = Set(controller.availableWeekdays ?? [])
                  if value { days.insert(day) } else { days.remove(day) }
                  controller.availableWeekdays = days.sorted()
                })
            )
            .accessibilityIdentifier("advice.weekday.\(day)")
          }
          Button(L10n.text("health.trainingadviceview.clear.day.selection.3525f4")) { controller.availableWeekdays = nil }
            .accessibilityIdentifier("advice.schedule.clear")
        }
      }
      Section {
        Button(L10n.text("health.trainingadviceview.view.today.s.advice.ae535c")) { controller.refresh() }
          .accessibilityIdentifier("advice.refresh")
      }
      if let message = controller.errorMessage {
        Section { Text(message).foregroundStyle(.secondary) }
      } else if let evaluation = controller.evaluation {
        Section(L10n.text("health.trainingadviceview.today.s.advice.d93d0e")) {
          if !evaluation.blockedMuscles.isEmpty {
            Label(
              L10n.text("health.trainingadviceview.additional.pain.or.movement.limits.training.9feb7a", String(evaluation.blockedMuscles.map(\.displayName).joined(separator: L10n.language == .english ? ", " : "、"))),
              systemImage: "exclamationmark.triangle"
            )
            .font(.subheadline)
            .foregroundStyle(.orange)
            .accessibilityIdentifier("advice.restrictedMuscles")
          }
          ForEach(evaluation.candidates) { candidate in
            candidateRow(candidate)
          }
        }
        if controller.activeWorkout == nil, let parameterActionID,
          let candidate = evaluation.candidates.first(where: { $0.id == parameterActionID })
        {
          Section(L10n.text("health.trainingadviceview.choose.parameters.for.this.workout.58299a")) {
            ForEach(candidate.allowedParameters, id: \.name) { allowed in
              Stepper(
                L10n.text("health.trainingadviceview.parameter.value",
                  allowed.name == "minimumRIR" ? L10n.text("health.trainingadviceview.minimum.reps.in.reserve.355e09") : L10n.text("health.trainingadviceview.working.sets.to.retain.3952d1"),
                  Int(parameterValues[allowed.name] ?? allowed.minimum).formatted(.number.locale(L10n.locale)),
                  allowed.unit == .percent ? "%" : L10n.text("health.trainingadviceview.reps.793578")),
                value: Binding(
                  get: { parameterValues[allowed.name] ?? allowed.minimum },
                  set: { parameterValues[allowed.name] = $0 }),
                in: allowed.minimum...allowed.maximum,
                step: allowed.name == "minimumRIR" ? 1 : 5
              )
              .accessibilityIdentifier("advice.parameter.\(allowed.name)")
            }
            Button(L10n.text("health.trainingadviceview.continue.with.these.parameters.1bd635")) { pendingActionID = parameterActionID }
              .accessibilityIdentifier("advice.parameters.confirm")
          }
        }
        Section {
          Text(L10n.text("health.trainingadviceview.advice.uses.current.records.and.your.c85a7b"))
            .font(.caption).foregroundStyle(.secondary)
        }
      } else {
        Section {
          Text(L10n.text("health.trainingadviceview.choose.a.template.to.view.advice.a404c9"))
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle(L10n.text("health.trainingadviceview.training.advice.d3707a"))
    .accessibilityIdentifier("advice.screen")
    .onAppear { controller.loadRoutines() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { controller.loadRoutines() }
    }
    .confirmationDialog(
      L10n.text("health.trainingadviceview.start.a.workout.using.this.advice.c15226"),
      isPresented: Binding(
        get: { pendingActionID != nil },
        set: { if !$0 { pendingActionID = nil } }),
      titleVisibility: .visible
    ) {
      Button(L10n.text("health.trainingadviceview.confirm.and.start.c1b24a")) { adoptPending() }
      Button(L10n.text("health.trainingadviceview.cancel.4d0b46"), role: .cancel) { pendingActionID = nil }
    } message: {
      Text(L10n.text("health.trainingadviceview.a.new.workout.in.progress.will.2cf232"))
    }
    .alert(
      L10n.text("health.trainingadviceview.could.not.start.workout.794e41"),
      isPresented: Binding(
        get: { actionError != nil }, set: { if !$0 { actionError = nil } }
      )
    ) {
      Button(L10n.text("health.trainingadviceview.ok.cb63c6"), role: .cancel) {}
    } message: {
      Text(actionError.map { L10n.text($0) } ?? L10n.text("health.trainingadviceview.refresh.and.try.again.507e0f"))
    }
    .sheet(item: $checkInDraft, onDismiss: { controller.refresh() }) { draft in
      RecoveryCheckInView(
        repository: controller.repository,
        suggestedMuscles: controller.evaluation?.blockedMuscles ?? [], draft: draft)
    }
  }

  @ViewBuilder
  private func candidateRow(_ candidate: RecommendationCandidate) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title(for: candidate.action)).font(.headline)
      Text(explanation(for: candidate.action)).font(.subheadline).foregroundStyle(.secondary)
      if let reason = controller.evaluation?.primaryReasonsByAction[candidate.actionID] {
        Label(reasonText(reason, action: candidate.action), systemImage: "info.circle")
          .font(.subheadline)
          .accessibilityIdentifier("advice.reason.\(candidate.action.rawValue)")
        if candidate.action != .lightActivity && reasonHasCheckIn(reason) {
          Button(L10n.text("health.trainingadviceview.view.or.edit.today.s.check.fcfaea")) { openCheckIn() }
            .accessibilityIdentifier("advice.editCheckIn")
        }
      }
      if let plan = controller.evaluation?.plansByAction[candidate.actionID],
        let routine = controller.routines.first(where: { $0.id == plan.id })
      {
        Text(L10n.text("health.trainingadviceview.template.e97a69", String(routine.name))).font(.caption).foregroundStyle(.secondary)
      }
      if candidate.action == .reviewNutrition, let onOpenNutrition {
        Button(L10n.text("health.trainingadviceview.view.nutrition.trends.107102"), action: onOpenNutrition)
          .accessibilityIdentifier("advice.openNutrition")
      } else if candidate.action == .choosePlan, let onOpenRecovery {
        Button(L10n.text("health.trainingadviceview.view.recovery.records.27666f"), action: onOpenRecovery)
          .accessibilityIdentifier("advice.openRecovery")
      } else if isStartable(candidate) && controller.activeWorkout == nil {
        Button(L10n.text("health.trainingadviceview.choose.parameters.and.start.db4831")) {
          parameterValues = Dictionary(
            uniqueKeysWithValues: candidate.allowedParameters.map { ($0.name, $0.minimum) })
          if candidate.allowedParameters.isEmpty {
            pendingActionID = candidate.actionID
          } else {
            parameterActionID = candidate.actionID
          }
        }
        .accessibilityIdentifier("advice.start.\(candidate.action.rawValue)")
      }
    }
  }

  private func isStartable(_ candidate: RecommendationCandidate) -> Bool {
    [.keepPlan, .reduceSets, .increaseRIR, .swapTrainingDay].contains(candidate.action)
  }

  private func adoptPending() {
    guard let actionID = pendingActionID else { return }
    pendingActionID = nil
    do {
      let workout = try controller.adopt(actionID: actionID, parameters: parameterValues)
      onStartWorkout(workout)
    } catch TrainingAdviceAdoptionError.inProgressWorkout {
      actionError = "health.trainingadviceview.a.workout.is.already.in.progress.99115d"
    } catch TrainingAdviceAdoptionError.templateChanged {
      actionError = "health.trainingadviceview.the.selected.or.alternative.template.changed.0d8d84"
    } catch TrainingAdviceAdoptionError.recordsChanged {
      actionError = "health.trainingadviceview.check.in.schedule.or.workout.records.ebcef2"
    } catch {
      actionError = "health.trainingadviceview.the.workout.could.not.be.saved.41cb59"
    }
  }

  private func openCheckIn() {
    do {
      let now = controller.now()
      let timeZone = controller.timeZone()
      let today = AnalysisFingerprint.localDate(now, timeZone: timeZone)
      checkInDraft = try controller.repository.manualRecords().checkIns.first {
        $0.localDate == today && $0.timeZoneIdentifier == timeZone.identifier
      } ?? .init(
        id: UUID(), localDate: today, timeZoneIdentifier: timeZone.identifier,
        updatedAt: now)
    } catch {
      actionError = "health.trainingadviceview.today.s.check.in.could.not.99489c"
    }
  }

  private func reasonHasCheckIn(_ reason: TrainingAdviceReason) -> Bool {
    switch reason {
    case .tiredCheckIn, .restrictedMuscles, .unverifiedMappingWithRestriction,
      .significantSoreness:
      true
    default: false
    }
  }

  private func reasonText(_ reason: TrainingAdviceReason, action: RecommendationAction) -> String {
    switch reason {
    case .unavailableToday: L10n.text("health.trainingadviceview.today.is.not.among.your.available.a80a0d")
    case .noWeeklyTrainingDays: L10n.text("health.trainingadviceview.your.profile.has.0.training.days.e0b830")
    case .tiredCheckIn: L10n.text("health.trainingadviceview.you.recorded.feeling.tired.today.so.c683e9")
    case .systemicLimited: L10n.text("health.trainingadviceview.systemic.recovery.status.indicates.limited.training.d9e389")
    case .systemicLow: L10n.text("health.trainingadviceview.systemic.recovery.status.prioritizes.recovery.bd9b09")
    case .restrictedMuscles(let muscles):
      action == .swapTrainingDay
        ? L10n.text("health.trainingadviceview.the.original.template.involves.flagged.for.88df60", String(muscles.map(\.displayName).joined(separator: L10n.language == .english ? ", " : "、")))
        : L10n.text("health.trainingadviceview.pain.or.limited.movement.is.recorded.e214b5", String(muscles.map(\.displayName).joined(separator: L10n.language == .english ? ", " : "、")))
    case .unverifiedMappingWithRestriction:
      L10n.text("health.trainingadviceview.pain.or.limited.movement.is.recorded.bcb842")
    case .significantSoreness: L10n.text("health.trainingadviceview.related.muscles.have.significant.soreness.recorded.5bbebc")
    case .recentWorkingSets(let count): L10n.text("health.trainingadviceview.related.muscles.completed.working.sets.in.68fb1d", count)
    case .reducedReadiness: L10n.text("health.trainingadviceview.the.selected.muscles.are.not.ready.10aa2e")
    case .insufficientCoverage: L10n.text("health.trainingadviceview.the.selected.template.s.exercise.mappings.5ffe50")
    case .noSelectedPlan: L10n.text("health.trainingadviceview.no.template.is.selected.for.this.d189ff")
    case .ready: L10n.text("health.trainingadviceview.current.records.for.the.selected.muscles.67f9f4")
    case .nutritionDifference: L10n.text("health.trainingadviceview.food.records.differ.from.targets.and.5ec170")
    }
  }

  private func weekdayName(_ day: Int) -> String {
    [L10n.text("health.trainingadviceview.sunday.c34057"), L10n.text("health.trainingadviceview.monday.792c34"), L10n.text("health.trainingadviceview.tuesday.8f0344"), L10n.text("health.trainingadviceview.wednesday.254556"), L10n.text("health.trainingadviceview.thursday.18f1fd"), L10n.text("health.trainingadviceview.friday.4344fc"), L10n.text("health.trainingadviceview.saturday.f0c619")][day - 1]
  }

  private func title(for action: RecommendationAction) -> String {
    switch action {
    case .keepPlan: L10n.text("health.trainingadviceview.use.selected.template.3d49bc")
    case .reduceSets: L10n.text("health.trainingadviceview.reduce.working.sets.e29d3d")
    case .increaseRIR: L10n.text("health.trainingadviceview.keep.more.reps.in.reserve.f3f61c")
    case .swapTrainingDay: L10n.text("health.trainingadviceview.use.alternative.template.448c80")
    case .rest: L10n.text("health.trainingadviceview.rest.d172c6")
    case .lightActivity: L10n.text("health.trainingadviceview.optional.light.activity.dd4c0f")
    case .choosePlan: L10n.text("health.trainingadviceview.review.template.and.recovery.first.d75aba")
    case .reviewNutrition: L10n.text("health.trainingadviceview.review.nutrition.targets.and.records.35a35e")
    }
  }

  private func explanation(for action: RecommendationAction) -> String {
    switch action {
    case .keepPlan: L10n.text("health.trainingadviceview.current.records.allow.the.selected.template.568686")
    case .reduceSets: L10n.text("health.trainingadviceview.keep.working.sets.within.the.suggested.c6be9c")
    case .increaseRIR: L10n.text("health.trainingadviceview.target.rir.is.a.training.cue.61eea5")
    case .swapTrainingDay: L10n.text("health.trainingadviceview.use.only.the.alternative.template.you.5d7fda")
    case .rest: L10n.text("health.trainingadviceview.current.records.suggest.rest.today.no.a45439")
    case .lightActivity: L10n.text("health.trainingadviceview.choose.light.activity.based.on.how.f674a3")
    case .choosePlan: L10n.text("health.trainingadviceview.training.or.recovery.evidence.is.insufficient.0285fe")
    case .reviewNutrition: L10n.text("health.trainingadviceview.nutrition.differences.are.reviewed.separately.and.b52c3a")
    }
  }
}
