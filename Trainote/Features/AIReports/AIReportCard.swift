import SwiftUI

/// Read-only card. Applying candidates, changing goals, and navigation remain F's responsibility.
struct AIReportCard: View {
  let content: AIReportContent
  var isHistory = false
  var now = Date.now
  var factLabel: (MetricFact) -> String = { _ in L10n.text("health.aireportcard.recorded.metric.db09dd") }
  var onDetails: () -> Void = {}

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label(content.report.isLocalFallback ? L10n.text("health.aireportcard.basic.report.9a5716") : L10n.text("health.aireportcard.ai.reports.9885c1"), systemImage: "text.document")
          .font(.headline)
        Spacer()
        if isHistory { Text(L10n.text("health.aireportcard.history.19e0e3")).font(.caption).foregroundStyle(.secondary) }
        else if content.isExpired(at: now) { Text(L10n.text("health.aireportcard.needs.update.30e81c")).font(.caption).foregroundStyle(.secondary) }
      }
      Text(ReportPresentation.summary(content.report))
      ForEach(Array(content.report.observations.enumerated()), id: \.offset) { _, observation in
        VStack(alignment: .leading, spacing: 4) {
          if let fact = content.input.facts.first(where: { observation.evidenceIDs.contains($0.id) }) {
            Text(factLabel(fact)).font(.subheadline.weight(.medium))
          }
          Text(ReportPresentation.supports(content.report)
            ? ReportPresentation.display(observation, facts: content.input.facts) : observation.text)
            .font(.subheadline).foregroundStyle(.secondary)
        }
      }
      ForEach(Array(content.report.recommendations.enumerated()), id: \.offset) { _, recommendation in
        Text(ReportPresentation.supports(content.report)
          ? ReportPresentation.recommendation(recommendation.text) : recommendation.text).font(.subheadline)
      }
      Button(L10n.text("health.aireportcard.view.evidence.and.details.1d9ddc"), action: onDetails).font(.subheadline)
      Text(L10n.text("health.aireportcard.valid.until.9dc24f", String(content.report.validUntil.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))))
        .font(.caption).foregroundStyle(.secondary)
    }
    .padding()
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    .accessibilityElement(children: .contain)
  }
}
