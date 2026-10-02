import SwiftUI

/// Read-only card. Applying candidates, changing goals, and navigation remain F's responsibility.
struct AIReportCard: View {
  let content: AIReportContent
  var isHistory = false
  var now = Date.now
  var factLabel: (MetricFact) -> String = { _ in "记录指标" }
  var onDetails: () -> Void = {}

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label(content.report.isLocalFallback ? "基础报告" : "AI 报告", systemImage: "text.document")
          .font(.headline)
        Spacer()
        if isHistory { Text("历史记录").font(.caption).foregroundStyle(.secondary) }
        else if content.isExpired(at: now) { Text("待更新").font(.caption).foregroundStyle(.secondary) }
      }
      Text(content.report.summary)
      ForEach(Array(content.report.observations.enumerated()), id: \.offset) { _, observation in
        VStack(alignment: .leading, spacing: 4) {
          if let fact = content.input.facts.first(where: { observation.evidenceIDs.contains($0.id) }) {
            Text(factLabel(fact)).font(.subheadline.weight(.medium))
          }
          Text(ReportText.display(observation, facts: content.input.facts))
            .font(.subheadline).foregroundStyle(.secondary)
        }
      }
      ForEach(Array(content.report.recommendations.enumerated()), id: \.offset) { _, recommendation in
        Text(recommendation.text).font(.subheadline)
      }
      Button("查看依据与说明", action: onDetails).font(.subheadline)
      Text(content.report.generatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
    }
    .padding()
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    .accessibilityElement(children: .contain)
  }
}
