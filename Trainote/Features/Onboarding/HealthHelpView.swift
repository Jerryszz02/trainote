import SwiftUI

/// Bundled prose remains readable without an internet connection.
struct HealthHelpView: View {
  var body: some View {
    List {
      Section(L10n.text("health.healthhelpview.methods.and.scope.16b0da")) {
        Text(
          L10n.text("health.healthhelpview.trend.and.recovery.analysis.uses.workout.c38346")
        )
        Text(L10n.text("health.healthhelpview.the.recovery.index.estimates.training.readiness.54ffcb"))
        Text(L10n.text("health.healthhelpview.general.nutrition.suggestions.are.for.healthy.2d4323"))
      }
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
      }
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
      }
      Section(L10n.text("health.healthhelpview.personal.calibration.and.reset.c88df2")) {
        Text(
          L10n.text("health.healthhelpview.calibration.reads.the.last.90.days.44bf37")
        )
        Text(
          L10n.text("health.healthhelpview.candidate.parameters.must.outperform.both.baseline.b85e6a")
        )
        Text(L10n.text("health.healthhelpview.reset.personal.calibration.on.the.recovery.b20b1b"))
      }
      Section(L10n.text("health.healthhelpview.data.and.apple.health.20baa0")) {
        Text(L10n.text("health.healthhelpview.manual.records.include.workouts.rir.food.da9aac"))
        Text(L10n.text("health.healthhelpview.to.manage.read.access.open.health.14b60c"))
        Text(
          L10n.text("health.healthhelpview.you.can.share.only.some.data.30e895"))
        Text(L10n.text("health.healthhelpview.sync.runs.on.foreground.refresh.and.735b9a"))
      }
      Section(L10n.text("health.healthhelpview.ai.and.deepseek.a6db6a")) {
        Text(L10n.text("health.healthhelpview.basic.reports.organize.current.trends.recovery.38a6a9"))
        Text(
          L10n.text("health.healthhelpview.ai.consent.is.separate.from.the.3665a4")
        )
        Text(
          L10n.text("health.healthhelpview.when.enabled.reports.send.only.necessary.42d36d")
        )
        Text(L10n.text("health.healthhelpview.the.provider.api.s.retention.reuse.b014f7"))
      }
      Section(L10n.text("health.healthhelpview.storage.withdrawal.and.deletion.f403ec")) {
        Text(L10n.text("health.healthhelpview.manual.records.stay.on.this.device.769a6c"))
        Text(L10n.text("health.healthhelpview.disconnecting.health.stops.sync.clears.imported.00d82a"))
        Text(
          L10n.text("health.healthhelpview.turning.off.ai.cancels.future.requests.5907d2")
        )
      }
      Section(L10n.text("health.healthhelpview.backups.v1.v2.582936")) {
        Text(
          L10n.text("health.healthhelpview.exports.use.v2.json.both.v1.a5b92c")
        )
        Text(
          L10n.text("health.healthhelpview.restore.checks.ids.and.skips.records.302a0e")
        )
      }
      Section(L10n.text("health.healthhelpview.help.and.contact.7cca8d")) {
        Text(L10n.text("health.healthhelpview.report.problems.on.the.project.s.5556e5"))
        Link(
          L10n.text("health.healthhelpview.contact.the.maintainer.on.github.d4bfc8"),
          destination: URL(string: "https://github.com/Jerryszz02/trainote/issues")!)
      }
    }
    .navigationTitle(L10n.text("health.healthhelpview.methods.and.data.use.93b2bb"))
    .navigationBarTitleDisplayMode(.inline)
  }
}
