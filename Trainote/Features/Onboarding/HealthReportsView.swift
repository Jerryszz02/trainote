import SwiftUI

struct HealthReportsView: View {
  @Environment(\.scenePhase) private var scenePhase
  let integration: HealthReportIntegration
  @State private var type: ReportType = .today
  @State private var showDetails = false

  var body: some View {
    List {
      Section {
        Picker(L10n.text("health.healthreportsview.report.scope.6c0964"), selection: $type) {
          Text(L10n.text("health.healthreportsview.today.574cd4")).tag(ReportType.today)
          Text(L10n.text("health.healthreportsview.trends.376df6")).tag(ReportType.trend)
          Text(L10n.text("health.healthreportsview.recovery.79748c")).tag(ReportType.recovery)
          Text(L10n.text("health.healthreportsview.this.week.e16e82")).tag(ReportType.weekly)
        }
        .accessibilityIdentifier("reports.type")
        Button(L10n.text("health.healthreportsview.refresh.report.ec87f6")) { Task { await integration.refresh(type: type) } }
          .disabled(integration.isRefreshing)
          .accessibilityIdentifier("reports.refresh")
      }
      if let content = integration.content, content.input.reportType == type {
        Section {
          AIReportCard(content: content, factLabel: HealthReportCopy.label) { showDetails = true }
            .accessibilityIdentifier("reports.current")
        }
        if let message = integration.errorMessage {
          Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
        }
      } else if integration.isRefreshing {
        Section { ProgressView(L10n.text("health.healthreportsview.reading.local.records.95272c")) }
      } else {
        Section {
          Text(integration.errorMessage ?? L10n.text("health.healthreportsview.the.current.report.needs.updating.refresh.89b72a"))
            .foregroundStyle(.secondary)
        }
      }
      if !integration.isConfigured {
        Section {
          Text(L10n.text("health.healthreportsview.basic.reports.are.generated.locally.ai.ffd0d4"))
            .font(.footnote).foregroundStyle(.secondary)
            .accessibilityIdentifier("reports.localOnly")
        }
      }
      Section {
        NavigationLink(L10n.text("health.healthreportsview.historical.ai.reports.4adc1e")) { HealthReportHistoryView(integration: integration) }
          .accessibilityIdentifier("reports.history")
        NavigationLink(L10n.text("health.healthreportsview.methods.privacy.and.data.use.7b28ee")) { HealthHelpView() }
      }
    }
    .navigationTitle(L10n.text("health.healthreportsview.analysis.reports.84de87"))
    .navigationBarTitleDisplayMode(.inline)
    .task(id: type) { await integration.refresh(type: type) }
    .refreshable { await integration.refresh(type: type) }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await integration.refresh(type: type) } }
    }
    .navigationDestination(isPresented: $showDetails) {
      if let content = integration.content {
        HealthReportEvidenceView(content: content)
      } else {
        ContentUnavailableView(
          L10n.text("health.healthreportsview.report.expired.eb3415"), systemImage: "arrow.clockwise", description: Text(L10n.text("health.healthreportsview.go.back.and.refresh.the.report.dee17a")))
      }
    }
  }
}

private struct HealthReportHistoryView: View {
  let integration: HealthReportIntegration
  @State private var selectedReport: AIReportContent?
  @State private var showDetails = false

  var body: some View {
    List {
      if integration.history.isEmpty {
        ContentUnavailableView(
          L10n.text("health.healthreportsview.no.historical.ai.reports.9eaa66"), systemImage: "clock",
          description: Text(L10n.text("health.healthreportsview.when.ai.reports.become.available.successfully.ce6128"))
        )
        .accessibilityIdentifier("reports.history.empty")
      }
      ForEach(integration.history) { content in
        Section {
          AIReportCard(content: content, isHistory: true, factLabel: HealthReportCopy.label) {
            selectedReport = content
            showDetails = true
          }
        }
      }
    }
    .navigationTitle(L10n.text("health.healthreportsview.historical.ai.reports.4adc1e"))
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(isPresented: $showDetails) {
      if let selectedReport, integration.history.contains(where: { $0.id == selectedReport.id }) {
        HealthReportEvidenceView(content: selectedReport)
      } else {
        ContentUnavailableView(L10n.text("health.healthreportsview.report.deleted.aa1129"), systemImage: "text.document")
      }
    }
  }
}

private struct HealthReportEvidenceView: View {
  let content: AIReportContent
  var body: some View {
    List {
      Section(L10n.text("health.healthreportsview.analysis.at.the.time.6ae3cf")) {
        LabeledContent(
          L10n.text("health.healthreportsview.records.through.dfa634"), value: content.input.asOf.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))
        Text(L10n.text("health.healthreportsview.values.come.from.local.rules.and.ed2907"))
          .font(.footnote).foregroundStyle(.secondary)
      }
      Section(L10n.text("health.healthreportsview.facts.and.evidence.8e249b")) {
        ForEach(ReportFactSelection.facts(content.input), id: \.id) { fact in
          VStack(alignment: .leading, spacing: 4) {
            Text(HealthReportCopy.label(fact)).font(.headline)
            Text(
              ReportPresentation.display(
                .init(text: ReportText.observation(fact), evidenceIDs: [fact.id]), facts: [fact])
            )
            .foregroundStyle(.secondary)
            Text(
              L10n.text("health.healthreportsview.period.f017c8", String(fact.window.start.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L10n.locale))), String(fact.window.end.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L10n.locale))))
            )
            .font(.caption).foregroundStyle(.secondary)
            Text(
              fact.sources.map { source in
                switch source.kind {
                case .manual: return L10n.text("health.healthreportsview.manual.records.d98299")
                case .healthKit: return L10n.text("health.healthreportsview.apple.health.6de270")
                case .calculation: return L10n.text("health.healthreportsview.local.calculation.6c8568")
                }
              }.uniqued().joined(separator: L10n.language == .english ? ", " : "、")
            )
            .font(.caption).foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("reports.fact.\(fact.metric)")
        }
      }
      Section { NavigationLink(L10n.text("health.healthreportsview.full.methods.and.data.use.b1ffd1")) { HealthHelpView() } }
    }
    .navigationTitle(L10n.text("health.healthreportsview.report.evidence.cf091a"))
    .navigationBarTitleDisplayMode(.inline)
  }
}

enum HealthReportCopy {
  static func label(_ fact: MetricFact) -> String {
    let trendLabel = fact.trendTitle
    if trendLabel != fact.metric { return trendLabel }
    let labels: [String: String] = [
      "weight.representative": L10n.text("health.healthreportsview.representative.daily.weight.2da445"),
      "weight.weeklyChange": L10n.text("health.healthreportsview.weekly.weight.change.02cb7a"),
      "diet.recordedMeanCalories": L10n.text("health.healthreportsview.recorded.average.daily.calories.40b1c1"),
      "diet.calibratedIntakeReference": L10n.text("health.healthreportsview.calibrated.intake.reference.2817ed"),
      "recovery.unallocatedRecords": L10n.text("health.healthreportsview.records.without.allocated.muscles.5258f3"),
      "recovery.readiness": L10n.text("health.healthreportsview.estimated.muscle.readiness.83a407"),
      "recovery.residualLoad": L10n.text("health.healthreportsview.estimated.remaining.load.275ec1"),
      "recovery.lastSessionLoad": L10n.text("health.healthreportsview.latest.workout.load.1885fa"),
      "recovery.tau": L10n.text("health.healthreportsview.recovery.time.parameter.c598e4"),
      "recovery.externalWorkoutDuration": L10n.text("health.healthreportsview.external.workout.duration.e5d32c"),
      "recovery.feeling": L10n.text("health.healthreportsview.today.s.check.in.abc88b"),
      "recovery.sleepFeeling": L10n.text("health.healthreportsview.perceived.sleep.f21dc3"),
      "recommendation.selectedPlan": L10n.text("health.healthreportsview.template.for.this.workout.299a26"),
      "recommendation.availableToday": L10n.text("health.healthreportsview.today.s.training.availability.037220"),
      "recommendation.trainingDaysPerWeek": L10n.text("health.healthreportsview.weekly.training.schedule.b7ee28"),
      "recommendation.painOrLimitation": L10n.text("health.healthreportsview.pain.or.movement.limits.a5fe16"),
      "recommendation.recentWorkingSets": L10n.text("health.healthreportsview.recent.working.sets.8ff387"),
      "recommendation.significantSoreness": L10n.text("health.healthreportsview.significant.soreness.d8d9c9"),
      "recommendation.feeling.tired": L10n.text("health.healthreportsview.feeling.tired.cd1942"),
    ]
    var label = labels[fact.metric]
    if label == nil, fact.metric.hasSuffix(".soreness") { label = L10n.text("health.healthreportsview.soreness.records.a0d3d1") }
    if label == nil, fact.metric.hasSuffix(".pain") { label = L10n.text("health.healthreportsview.pain.records.687527") }
    if label == nil, fact.metric.hasSuffix(".movementLimitation") { label = L10n.text("health.healthreportsview.movement.limits.44018b") }
    if label == nil, fact.metric.hasPrefix("recommendation.goal.") { label = L10n.text("health.healthreportsview.goal.direction.4a9679") }
    if label == nil, fact.metric.hasPrefix("recommendation.systemic.") { label = L10n.text("health.healthreportsview.systemic.status.116dd1") }
    if label == nil, fact.metric.hasPrefix("recovery.systemic.") {
      let measure =
        fact.metric.contains("sleep.duration")
        ? L10n.text("health.healthreportsview.sleep.ca5f73")
        : fact.metric.contains("restingHeartRate") ? L10n.text("health.healthreportsview.resting.heart.rate.ca24f8") : "HRV (SDNN)"
      label =
        measure
        + (fact.metric.hasSuffix("baseline")
          ? L10n.text("health.healthreportsview.personal.baseline.ab4294")
          : fact.metric.hasSuffix("deviationPercent") ? L10n.text("health.healthreportsview.change.from.baseline.f8fb69") : L10n.text("health.healthreportsview.recent.records.3b6770"))
    }
    let muscle = MuscleID.allCases.first { fact.id.contains(".\($0.rawValue).") }
    return [muscle?.displayName, label ?? L10n.text("health.healthreportsview.recorded.metric.db09dd")].compactMap { $0 }.joined(separator: " · ")
  }
}

extension Array where Element == String {
  fileprivate func uniqued() -> [String] { Array(Set(self)).sorted() }
}
