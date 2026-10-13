import SwiftUI

/// The parent owns NavigationStack and shared service assembly.
struct RecoveryView: View {
  @Environment(\.scenePhase) private var scenePhase
  let repository: any AnalysisRepository
  let healthData: (any HealthDataProviding)?
  let calculator: any RecoveryCalculating
  var onShowMethods: (() -> Void)? = nil
  var resetCalibration: (() -> Void)? = nil
  @State private var result: RecoveryResult?
  @State private var selected: MuscleID?
  @State private var checkInDraft: CheckInValue?
  @State private var manual: ManualHealthRecords?
  @State private var error: String?
  @State private var healthReadFailed = false
  @State private var showPrompt = false
  @State private var confirmingReset = false

  var body: some View {
    ScrollViewReader { scroll in
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if let error {
            ContentUnavailableView(
              L10n.text("health.recoveryview.analysis.could.not.be.updated.204ff8"), systemImage: "arrow.clockwise",
              description: Text(L10n.text(error)))
            Button(L10n.text("health.recoveryview.retry.e2d53a")) { reload() }
          } else if let result {
            VStack(alignment: .leading, spacing: 8) {
              Text(L10n.text("health.recoveryview.recovery.index.0cee65")).font(.title2.bold())
              Text(L10n.text("health.recoveryview.select.a.muscle.to.review.recent.415cc4")).foregroundStyle(.secondary)
            }
            BodyMapView(presentation: result.bodyMapPresentation(selected: selected)) { muscle in
              if selected == muscle {
                withAnimation { scroll.scrollTo(detailAnchor(for: muscle), anchor: .top) }
              } else {
                selected = muscle
              }
            }
            if let muscle = result.muscles.first(where: { $0.muscleID == selected }) {
              RecoveryMuscleDetail(
                muscle: muscle, result: result, onFeedback: { openCheckIn(muscle.muscleID) },
                onShowMethods: onShowMethods)
                .id(detailAnchor(for: muscle.muscleID))
            }
            RecoverySystemicCard(result: result)
            if healthReadFailed {
              Text(L10n.text("health.recoveryview.health.data.could.not.be.read.d10ecc")).font(.caption).foregroundStyle(.secondary)
            }
            if showPrompt {
              HStack {
                VStack(alignment: .leading) {
                  Text(L10n.text("health.recoveryview.how.do.you.feel.today.7be6f0")).font(.headline)
                  Text(L10n.text("health.recoveryview.add.a.quick.check.in.or.db5806")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.text("health.recoveryview.fill.in.a2272f")) { openCheckIn() }
                Button(L10n.text("health.recoveryview.skip.31a985")) { showPrompt = false }
              }
            }
            Button(L10n.text("health.recoveryview.record.or.edit.today.s.check.268c2c")) { openCheckIn() }
              .accessibilityIdentifier("recovery.checkIn.open")
            if let resetCalibration {
              Button(L10n.text("health.recoveryview.reset.personal.calibration.a77810")) { confirmingReset = true }
                .confirmationDialog(
                  L10n.text("health.recoveryview.start.collecting.new.calibration.records.now.4ae9c0"), isPresented: $confirmingReset, titleVisibility: .visible
                ) {
                  Button(L10n.text("health.recoveryview.reset.calibration.1892ea")) {
                    resetCalibration()
                    reload()
                  }
                  Button(L10n.text("health.recoveryview.cancel.4d0b46"), role: .cancel) {}
                } message: {
                  Text(L10n.text("health.recoveryview.workout.and.check.in.history.is.6ae7e7"))
                }
            }
            if let onShowMethods { Button(L10n.text("health.recoveryview.methods.and.data.use.df2501"), action: onShowMethods) }
          } else {
            ProgressView(L10n.text("health.recoveryview.reading.local.records.95272c"))
          }
        }.padding()
      }
      .onChange(of: selected) { _, muscle in
        guard let muscle else { return }
        withAnimation { scroll.scrollTo(detailAnchor(for: muscle), anchor: .top) }
      }
    }
    .navigationTitle(L10n.text("health.recoveryview.recovery.analysis.c172e5"))
    .accessibilityIdentifier("recovery.screen")
    .onAppear { reload() }
    .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
    .refreshable { reload() }
    .sheet(item: $checkInDraft, onDismiss: { reload() }) { draft in
      RecoveryCheckInView(repository: repository, suggestedMuscles: suggestedMuscles, draft: draft)
    }
  }

  private func detailAnchor(for muscle: MuscleID) -> String {
    "recovery.selectedDetail.\(muscle.rawValue)"
  }

  private var suggestedMuscles: [MuscleID] {
    let recent =
      result?.muscles.filter {
        $0.lastTrainedAt.map { Date.now.timeIntervalSince($0) <= 7 * 86_400 } == true || $0.hasPain
          || $0.hasMovementLimitation
      }.map(\.muscleID) ?? []
    return MuscleID.allCases.filter { recent.contains($0) || selected == $0 }
  }
  private func reload() {
    let now = Date.now
    let window = AnalysisWindow(
      start: now.addingTimeInterval(-Double(RecoveryParameters.inputDays) * 86_400), end: now)
    do {
      let health: HealthDataSnapshot
      do {
        health =
          try healthData?.localSnapshot(window: window) ?? .disconnected(window: window, asOf: now)
        healthReadFailed = false
      } catch {
        healthReadFailed = true
        health = .init(
          window: window, fetchedAt: now, isFresh: false, samples: [],
          statuses: HealthDataType.allCases.map {
            .init(type: $0, state: .failed, queriedAt: now, failure: .readFailed)
          })
      }
      let input = try repository.analysisInput(
        asOf: now, window: window, timeZone: .current, health: health)
      result = try calculator.calculate(input)
      manual = try repository.manualRecords()
      if let manual {
        showPrompt =
          (try? RecoveryCheckInPrompt.offer(
            repository: repository, records: manual, date: now, timeZone: .current)) ?? false
      }
      error = nil
    } catch {
      result = nil
      self.error = "health.recoveryview.reading.or.calculation.failed.existing.workout.fd7207"
    }
  }
  private func openCheckIn(_ muscle: MuscleID? = nil) {
    if let muscle { selected = muscle }
    let now = Date.now
    let today = AnalysisFingerprint.localDate(now, timeZone: .current)
    checkInDraft =
      manual?.checkIns.first {
        $0.localDate == today && $0.timeZoneIdentifier == TimeZone.current.identifier
      }
      ?? .init(
        id: UUID(), localDate: today, timeZoneIdentifier: TimeZone.current.identifier,
        updatedAt: now)
  }
}

private struct RecoveryMuscleDetail: View {
  let muscle: MuscleRecovery
  let result: RecoveryResult
  let onFeedback: () -> Void
  let onShowMethods: (() -> Void)?
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(muscle.muscleID.displayName).font(.title3.bold())
        Spacer()
        Text(muscle.score.map { "\(RecoveryParameters.displayedScore($0))/100" } ?? "—")
          .font(.title3.monospacedDigit()).foregroundStyle(RecoveryCopy.color(muscle.state))
      }
      Text(RecoveryCopy.state(muscle.state)).font(.headline)
      if muscle.hasPain { Label(L10n.text("health.recoveryview.pain.flagged.related.training.is.excluded.80c1e1"), systemImage: "exclamationmark.triangle") }
      if muscle.hasMovementLimitation {
        Label(L10n.text("health.recoveryview.limited.movement.flagged.related.training.is.d326c4"), systemImage: "exclamationmark.triangle")
      }
      if let date = muscle.lastTrainedAt {
        LabeledContent(L10n.text("health.recoveryview.last.workout.d330e0"), value: date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))
      }
      if let fact = result.facts.first(where: {
        $0.id == "recovery.\(muscle.muscleID.rawValue).lastLoad"
      }), let load = fact.value {
        LabeledContent(L10n.text("health.recoveryview.latest.weighted.working.sets.8b9560"), value: load.formatted(.number.precision(.fractionLength(1)).locale(L10n.locale)))
      }
      ForEach(muscle.influences, id: \.code) { influence in
        Text(RecoveryCopy.influence(influence.code)).font(.subheadline).foregroundStyle(.secondary)
      }
      if let coverage = muscle.coverage.first {
        Text(L10n.text("health.recoveryview.last.days.days.with.usable.records.3cddc0", String(coverage.expectedDays), String(coverage.observedDays)))
          .font(.caption).foregroundStyle(.secondary)
      }
      Button(L10n.text("health.recoveryview.update.this.muscle.s.check.in.016fd6"), action: onFeedback)
      if let onShowMethods { Button(L10n.text("health.recoveryview.about.the.score.2e7f5a"), action: onShowMethods) }
      Text(result.calculationVersion).font(.caption2).foregroundStyle(.secondary)
    }
    .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    .accessibilityIdentifier("recovery.detail.\(muscle.muscleID.rawValue)")
  }
}

private struct RecoverySystemicCard: View {
  let result: RecoveryResult
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(L10n.text("health.recoveryview.systemic.status.116dd1")).font(.headline)
      Text(RecoveryCopy.systemic(result.systemicState))
      if let feeling = result.facts.first(where: { $0.id == "recovery.feeling" })?.value {
        LabeledContent(L10n.text("health.recoveryview.today.s.check.in.abc88b"), value: feeling == 2 ? L10n.text("health.recoveryview.ok.27e4fe") : (feeling == 1 ? L10n.text("health.recoveryview.okay.f0aacc") : L10n.text("health.recoveryview.tired.8174d1")))
      }
      if let sleep = result.facts.first(where: { $0.id == "recovery.sleepFeeling" })?.value {
        LabeledContent(L10n.text("health.recoveryview.perceived.sleep.f21dc3"), value: sleep == 2 ? L10n.text("health.recoveryview.ok.27e4fe") : (sleep == 1 ? L10n.text("health.recoveryview.okay.f0aacc") : L10n.text("health.recoveryview.poor.8046a5")))
      }
      ForEach(["sleep.duration", "restingHeartRate", "heartRateVariabilitySDNN"], id: \.self) {
        metric in
        if let fact = result.facts.first(where: { $0.id == "recovery.systemic.\(metric).latest" }),
          let value = fact.value
        {
          LabeledContent(
            RecoveryCopy.metric(metric), value: RecoveryCopy.value(value, unit: fact.unit))
          if let baseline = result.facts.first(where: {
            $0.id == "recovery.systemic.\(metric).baseline"
          }) {
            if let value = baseline.value {
              Text(L10n.text("health.recoveryview.personal.baseline.1ce343", String(RecoveryCopy.value(value, unit: baseline.unit)))).font(.caption)
                .foregroundStyle(.secondary)
            } else {
              Text(L10n.text("health.recoveryview.building.a.personal.baseline.f1f535")).font(.caption).foregroundStyle(.secondary)
            }
          }
          if let deviation = result.facts.first(where: {
            $0.id == "recovery.systemic.\(metric).deviationPercent"
          })?.value {
            Text(L10n.text("health.recoveryview.from.baseline.6c59f5", String(deviation.formatted(.number.precision(.fractionLength(0)).locale(L10n.locale))))).font(
              .caption
            ).foregroundStyle(.secondary)
          }
        }
      }
      if result.facts.contains(where: { $0.id == "recovery.systemic.externalWorkout" }) {
        Text(L10n.text("health.recoveryview.external.workouts.from.apple.health.are.67eaae"))
          .font(.caption).foregroundStyle(.secondary)
      }
    }.padding().frame(maxWidth: .infinity, alignment: .leading)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
  }
}

enum RecoveryCopy {
  static func color(_ state: RecoveryState) -> Color {
    switch state {
    case .ready: .green
    case .moderate: .orange
    case .low, .limited: .red
    case .unknown: .secondary
    }
  }
  static func state(_ state: RecoveryState) -> String {
    switch state {
    case .ready: L10n.text("health.recoveryview.good.readiness.d4d8e0")
    case .moderate: L10n.text("health.recoveryview.train.moderately.726903")
    case .low: L10n.text("health.recoveryview.prioritize.recovery.41ef55")
    case .limited: L10n.text("health.recoveryview.training.limited.e1184e")
    case .unknown: L10n.text("health.recoveryview.waiting.for.records.dda84c")
    }
  }
  static func systemic(_ state: RecoveryState) -> String {
    switch state {
    case .ready: L10n.text("health.recoveryview.current.check.ins.or.personal.baselines.409d9e")
    case .moderate: L10n.text("health.recoveryview.watch.how.you.feel.and.recent.ee3afa")
    case .low, .limited: L10n.text("health.recoveryview.sustained.changes.with.fatigue.reduce.training.adfa04")
    case .unknown: L10n.text("health.recoveryview.not.enough.systemic.status.records.yet.6961a5")
    }
  }
  static func influence(_ code: String) -> String {
    switch code {
    case "recordedLoad": L10n.text("health.recoveryview.estimated.from.recorded.working.sets.rir.9fb233")
    case "unknownRIRPrior": L10n.text("health.recoveryview.some.sets.have.no.rir.default.04f5f5")
    case "historicalRolePrior": L10n.text("health.recoveryview.historical.set.types.are.unknown.counted.2c7f90")
    case "unallocatedExercise": L10n.text("health.recoveryview.unreviewed.exercises.unsupported.recording.modes.or.e7db9c")
    case "significantSoreness": L10n.text("health.recoveryview.significant.soreness.reduce.related.training.volume.0a6eb7")
    case "mildSoreness": L10n.text("health.recoveryview.mild.soreness.recorded.adjust.training.based.2492f9")
    case "excludeTraining": L10n.text("health.recoveryview.pain.and.limited.movement.are.independent.ce3fea")
    case "calibratedCandidate": L10n.text("health.recoveryview.personal.parameters.adjusted.conservatively.after.time.856857")
    default: L10n.text("health.recoveryview.not.enough.usable.recent.records.this.d711ed")
    }
  }
  static func metric(_ metric: String) -> String {
    switch metric {
    case "sleep.duration": L10n.text("health.recoveryview.recent.sleep.b25c17")
    case "restingHeartRate": L10n.text("health.recoveryview.resting.heart.rate.ca24f8")
    default: "HRV (SDNN)"
    }
  }
  static func value(_ value: Double, unit: MetricUnit) -> String {
    if unit == .seconds {
      return L10n.text("health.recoveryview.hours.89d17f", String((value / 3600).formatted(.number.precision(.fractionLength(1)).locale(L10n.locale))))
    }
    return
      "\(value.formatted(.number.precision(.fractionLength(0)).locale(L10n.locale))) \(unit == .milliseconds ? "ms" : L10n.text("health.recoveryview.beats.per.minute"))"
  }
}
