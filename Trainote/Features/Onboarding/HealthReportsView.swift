import SwiftUI

struct HealthReportsView: View {
  @Environment(\.scenePhase) private var scenePhase
  let integration: HealthReportIntegration
  @State private var type: ReportType = .today
  @State private var showDetails = false

  var body: some View {
    List {
      Section {
        Picker("报告范围", selection: $type) {
          Text("今日").tag(ReportType.today)
          Text("趋势").tag(ReportType.trend)
          Text("恢复").tag(ReportType.recovery)
          Text("本周").tag(ReportType.weekly)
        }
        .accessibilityIdentifier("reports.type")
        Button("刷新报告") { Task { await integration.refresh(type: type) } }
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
        Section { ProgressView("正在读取本地记录") }
      } else {
        Section {
          Text(integration.errorMessage ?? "当前报告需要更新，请刷新后查看。")
            .foregroundStyle(.secondary)
        }
      }
      if !integration.isConfigured {
        Section {
          Text("基础报告在本机生成。AI 报告待开放，当前不会发送记录。")
            .font(.footnote).foregroundStyle(.secondary)
            .accessibilityIdentifier("reports.localOnly")
        }
      }
      Section {
        NavigationLink("历史 AI 报告") { HealthReportHistoryView(integration: integration) }
          .accessibilityIdentifier("reports.history")
        NavigationLink("方法、隐私与数据使用") { HealthHelpView() }
      }
    }
    .navigationTitle("分析报告")
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
          "报告已失效", systemImage: "arrow.clockwise", description: Text("返回后刷新报告。"))
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
          "暂无历史 AI 报告", systemImage: "clock",
          description: Text("AI 报告开放后，成功生成的报告会保存在本机。基础报告随当前记录重新计算。")
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
    .navigationTitle("历史 AI 报告")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(isPresented: $showDetails) {
      if let selectedReport, integration.history.contains(where: { $0.id == selectedReport.id }) {
        HealthReportEvidenceView(content: selectedReport)
      } else {
        ContentUnavailableView("报告已删除", systemImage: "text.document")
      }
    }
  }
}

private struct HealthReportEvidenceView: View {
  let content: AIReportContent
  var body: some View {
    List {
      Section("当时的分析") {
        LabeledContent(
          "记录截止", value: content.input.asOf.formatted(date: .abbreviated, time: .shortened))
        Text("数值来自本地规则和记录。恢复分数与参数仍是工程估计；缺失记录保留为未知。历史建议不能直接开始训练。")
          .font(.footnote).foregroundStyle(.secondary)
      }
      Section("事实与依据") {
        ForEach(ReportFactSelection.facts(content.input), id: \.id) { fact in
          VStack(alignment: .leading, spacing: 4) {
            Text(HealthReportCopy.label(fact)).font(.headline)
            Text(
              ReportText.display(
                .init(text: ReportText.observation(fact), evidenceIDs: [fact.id]), facts: [fact])
            )
            .foregroundStyle(.secondary)
            Text(
              "统计区间：\(fact.window.start.formatted(date: .abbreviated, time: .omitted))—\(fact.window.end.formatted(date: .abbreviated, time: .omitted))"
            )
            .font(.caption).foregroundStyle(.secondary)
            Text(
              fact.sources.map { source in
                switch source.kind {
                case .manual: return "手动记录"
                case .healthKit: return "Apple 健康"
                case .calculation: return "本地计算"
                }
              }.uniqued().joined(separator: "、")
            )
            .font(.caption).foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("reports.fact.\(fact.metric)")
        }
      }
      Section { NavigationLink("完整方法与数据使用") { HealthHelpView() } }
    }
    .navigationTitle("报告依据")
    .navigationBarTitleDisplayMode(.inline)
  }
}

enum HealthReportCopy {
  static func label(_ fact: MetricFact) -> String {
    let trendLabel = fact.trendTitle
    if trendLabel != fact.metric { return trendLabel }
    let labels: [String: String] = [
      "weight.representative": "当日代表体重",
      "weight.weeklyChange": "每周体重变化",
      "diet.recordedMeanCalories": "已记录日均热量",
      "diet.calibratedIntakeReference": "校准摄入参考",
      "recovery.unallocatedRecords": "尚未分配肌群的记录",
      "recovery.readiness": "肌群准备度估计",
      "recovery.residualLoad": "剩余负荷估计",
      "recovery.lastSessionLoad": "最近一次训练负荷",
      "recovery.tau": "恢复时间参数",
      "recovery.externalWorkoutDuration": "外部训练时长",
      "recovery.feeling": "今日体感",
      "recovery.sleepFeeling": "主观睡眠",
      "recommendation.selectedPlan": "本次模板选择",
      "recommendation.availableToday": "今日可训练安排",
      "recommendation.trainingDaysPerWeek": "每周训练安排",
      "recommendation.painOrLimitation": "疼痛或活动限制",
      "recommendation.recentWorkingSets": "近期工作组",
      "recommendation.significantSoreness": "明显酸痛",
      "recommendation.feeling.tired": "疲惫体感",
    ]
    var label = labels[fact.metric]
    if label == nil, fact.metric.hasSuffix(".soreness") { label = "酸痛记录" }
    if label == nil, fact.metric.hasSuffix(".pain") { label = "疼痛记录" }
    if label == nil, fact.metric.hasSuffix(".movementLimitation") { label = "活动限制" }
    if label == nil, fact.metric.hasPrefix("recommendation.goal.") { label = "目标方向记录" }
    if label == nil, fact.metric.hasPrefix("recommendation.systemic.") { label = "全身状态" }
    if label == nil, fact.metric.hasPrefix("recovery.systemic.") {
      let measure =
        fact.metric.contains("sleep.duration")
        ? "睡眠"
        : fact.metric.contains("restingHeartRate") ? "静息心率" : "HRV（SDNN）"
      label =
        measure
        + (fact.metric.hasSuffix("baseline")
          ? "个人基线"
          : fact.metric.hasSuffix("deviationPercent") ? "相对基线变化" : "近期记录")
    }
    let muscle = MuscleID.allCases.first { fact.id.contains(".\($0.rawValue).") }
    return [muscle?.displayName, label ?? "记录指标"].compactMap { $0 }.joined(separator: " · ")
  }
}

extension Array where Element == String {
  fileprivate func uniqued() -> [String] { Array(Set(self)).sorted() }
}
