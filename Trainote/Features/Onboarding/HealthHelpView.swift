import SwiftUI

/// Bundled prose remains readable without an internet connection.
struct HealthHelpView: View {
  enum Topic: String, CaseIterable, Identifiable {
    case quickStart, nutrition, methods, trends, recovery, calibration, health, ai, storage, backup,
      sources, contact
    var id: String { rawValue }
    var title: String {
      switch self {
      case .quickStart: L10n.text("interaction.help.quickStart")
      case .nutrition: L10n.text("interaction.help.nutrition")
      case .methods: L10n.text("health.healthhelpview.methods.and.scope.16b0da")
      case .trends: L10n.text("health.healthhelpview.trends.and.weekly.nutrition.suggestions.24f35a")
      case .recovery: L10n.text("health.healthhelpview.how.the.recovery.index.works.1b0803")
      case .calibration: L10n.text("health.healthhelpview.personal.calibration.and.reset.c88df2")
      case .health: L10n.text("health.healthhelpview.data.and.apple.health.20baa0")
      case .ai: L10n.text("health.healthhelpview.ai.and.deepseek.a6db6a")
      case .storage: L10n.text("health.healthhelpview.storage.withdrawal.and.deletion.f403ec")
      case .backup: L10n.text("health.healthhelpview.backups.v1.v2.582936")
      case .sources: L10n.text("interaction.help.sources")
      case .contact: L10n.text("health.healthhelpview.help.and.contact.7cca8d")
      }
    }
  }
  @Environment(HealthFeatureAccess.self) private var access
  @Environment(ExerciseCatalog.self) private var catalog
  var topic: Topic? = nil
  var requestsAIConsent = false

  // Load bundled license documents once. All text is available without a network request.
  private static let notices: [(String, String?)] = [
    ("THIRD_PARTY_NOTICES", "md"), ("ANATOMY-PROVENANCE", "md"),
    ("ANATOMY-LICENSE", "txt"), ("EXERCISE-MEDIA-PROVENANCE", "md"),
    ("EXERCISE-MEDIA-LICENSE", "txt"), ("PROVENANCE", "md"), ("LICENSE", "txt"),
  ].map { name, ext in
    let text = Bundle.main.url(forResource: name, withExtension: ext)
      .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    return (name, text)
  }
  var body: some View {
    ScrollViewReader { scroll in
      List {
        Section(L10n.text("interaction.help.contents")) {
          ForEach(Topic.allCases) { destination in
            Button(destination.title) { scroll.scrollTo(destination, anchor: .top) }
              .accessibilityIdentifier("help.topic.\(destination.rawValue)")
          }
        }.id("contents")
        Section(L10n.text("interaction.help.quickStart")) {
          Text(L10n.text("interaction.help.startHelp"))
          Text(L10n.text("interaction.help.recordHelp"))
          Text(L10n.text("interaction.help.rirHelp"))
        }.id(Topic.quickStart)
        Section(L10n.text("interaction.help.nutrition")) {
          Text(
            L10n.text("interaction.help.portionHelp")
          )
          Text(NutritionMath.calorieCalculationNote)
          Text(L10n.text("interaction.help.reuseHelp"))
          Text(L10n.text("interaction.help.completeHelp"))
        }.id(Topic.nutrition)
        Section(L10n.text("health.healthhelpview.methods.and.scope.16b0da")) {
          Text(
            L10n.text("health.healthhelpview.trend.and.recovery.analysis.uses.workout.c38346")
          )
          Text(L10n.text("health.healthhelpview.the.recovery.index.estimates.training.readiness.54ffcb"))
          Text(
            L10n.text("health.healthhelpview.general.nutrition.suggestions.are.for.healthy.2d4323"))
        }.id(Topic.methods)
        Section(L10n.text("health.healthhelpview.trends.and.weekly.nutrition.suggestions.24f35a")) {
          Text(
            L10n.text("health.healthhelpview.a.representative.daily.weight.is.selected.13ddad")
          )
          Text(
            L10n.text("health.healthhelpview.weekly.adjustments.require.weight.records.spanning.caa175")
          )
          Text(
            L10n.text("health.healthhelpview.daily.intake.is.compared.with.the.1579a6")
          )
          Text(L10n.text("health.healthhelpview.these.ranges.weights.and.thresholds.are.d8a6e6"))
        }.id(Topic.trends)
        Section(L10n.text("health.healthhelpview.how.the.recovery.index.works.1b0803")) {
          Text(
            L10n.text("health.healthhelpview.only.completed.mapped.working.sets.are.d45810")
          )
          Text(
            L10n.text("health.healthhelpview.local.load.uses.the.last.28.5cb351")
          )
          Text(
            L10n.text("health.healthhelpview.the.exercise.catalog.contains.1.324.a9b89d")
          )
          Text(
            L10n.text("health.healthhelpview.sleep.resting.heart.rate.and.hrv.32467a")
          )
        }.id(Topic.recovery)
        Section(L10n.text("health.healthhelpview.personal.calibration.and.reset.c88df2")) {
          Text(
            L10n.text("health.healthhelpview.calibration.reads.the.last.90.days.44bf37")
          )
          Text(
            L10n.text("health.healthhelpview.candidate.parameters.must.outperform.both.baseline.b85e6a")
          )
          Text(L10n.text("health.healthhelpview.reset.personal.calibration.on.the.recovery.b20b1b"))
        }.id(Topic.calibration)
        Section(L10n.text("health.healthhelpview.data.and.apple.health.20baa0")) {
          Text(
            L10n.text("health.healthhelpview.manual.records.include.workouts.rir.food.da9aac"))
          Text(
            L10n.text("health.healthhelpview.to.manage.read.access.open.health.14b60c")
          )
          Text(
            L10n.text("health.healthhelpview.you.can.share.only.some.data.30e895")
          )
          Text(
            L10n.text("health.healthhelpview.sync.runs.on.foreground.refresh.and.735b9a"))
        }.id(Topic.health)
        Section(L10n.text("health.healthhelpview.ai.and.deepseek.a6db6a")) {
          Text(L10n.text("health.healthhelpview.basic.reports.organize.current.trends.recovery.38a6a9"))
          Text(L10n.text("interaction.help.aiHelp"))
          if requestsAIConsent {
            if access.reports.isConfigured {
              Text(L10n.text("interaction.help.aiDisableHelp"))
            } else {
              Text(access.reports.configurationMessage).accessibilityIdentifier(
                "health.aiUnavailable")
              Text(L10n.text("health.healthonboardingview.no.records.are.currently.sent.to.4a7205"))
            }
          }
          Text(
            L10n.text("health.healthhelpview.when.enabled.reports.send.only.necessary.42d36d")
          )
          Text(L10n.text("health.healthhelpview.the.provider.api.s.retention.reuse.b014f7"))
          if requestsAIConsent && access.reports.isConfigured {
            Button(L10n.text("health.healthonboardingview.agree.to.this.processing.and.enable.4e1fd9")) { Task { await access.enableAI() } }
              .disabled(access.isBusy || access.aiEnabled)
              .accessibilityIdentifier("health.aiConsent")
          }
        }.id(Topic.ai)
        Section(L10n.text("health.healthhelpview.storage.withdrawal.and.deletion.f403ec")) {
          Text(L10n.text("health.healthhelpview.manual.records.stay.on.this.device.769a6c"))
          Text(L10n.text("health.healthhelpview.disconnecting.health.stops.sync.clears.imported.00d82a"))
          Text(
            L10n.text("health.healthhelpview.turning.off.ai.cancels.future.requests.5907d2")
          )
        }.id(Topic.storage)
        Section(L10n.text("health.healthhelpview.backups.v1.v2.582936")) {
          Text(
            L10n.text("health.healthhelpview.exports.use.v2.json.both.v1.a5b92c")
          )
          Text(
            L10n.text("health.healthhelpview.restore.checks.ids.and.skips.records.302a0e")
          )
        }.id(Topic.backup)
        Section(L10n.text("interaction.help.sources")) {
          LabeledContent(
            L10n.text("interaction.help.version"),
            value: [
              Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion").map { "(\($0))" },
            ].compactMap { $0 }.joined(separator: " "))
          LabeledContent(L10n.text("settings.exerciseCount"), value: "\(catalog.items.count)")
          if let source = catalog.source, let url = URL(string: source.repository) {
            Link(L10n.text("settings.datasetRepository"), destination: url)
          }
          ForEach(Self.notices, id: \.0) { name, text in
            DisclosureGroup(name) {
              Text(text ?? L10n.text("interaction.help.licenseUnavailable"))
                .font(.footnote).textSelection(.enabled)
            }
            .accessibilityIdentifier("help.license.\(name)")
          }
        }.id(Topic.sources)
        Section(L10n.text("health.healthhelpview.help.and.contact.7cca8d")) {
          Text(L10n.text("health.healthhelpview.report.problems.on.the.project.s.5556e5"))
          Link(
            L10n.text("health.healthhelpview.contact.the.maintainer.on.github.d4bfc8"),
            destination: URL(string: "https://github.com/Jerryszz02/trainote/issues")!)
        }.id(Topic.contact)
      }
      .onAppear { if let topic { scroll.scrollTo(topic, anchor: .top) } }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(L10n.text("interaction.help.contents")) { scroll.scrollTo("contents", anchor: .top) }
            .accessibilityIdentifier("help.contents")
        }
      }
    }
    .navigationTitle(L10n.text("interaction.help.title"))
    .navigationBarTitleDisplayMode(.inline)
    .healthAccessError(access)
  }
}
