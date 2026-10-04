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
        Button("身体资料与目标方向") { showProfile = true }
          .accessibilityIdentifier("trend.profile")
        if let onOpenManualGoal { Button("编辑手动营养目标", action: onOpenManualGoal) }
        if let onOpenHelp { Button("计算方法与数据使用", action: onOpenHelp) }
      }
    }
    .navigationTitle("趋势分析")
    .accessibilityIdentifier("trend.screen")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("记录体重", systemImage: "plus") { showWeight = true }
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
      "未能完成",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: {
          if !$0 { model.errorMessage = nil }
        })
    ) {
      Button("好", role: .cancel) { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
    .confirmationDialog(
      "开启每周自动采用？", isPresented: $showAutomaticConfirmation, titleVisibility: .visible
    ) {
      Button("开启自动采用") {
        model.setMode(.automatic)
        model.reload()
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text("初始目标由你先采用。之后仅在记录充分且通过边界检查时，每 7 天最多调整一次，每次不超过 100 kcal 或当前目标的 5%。可随时暂停或撤销。")
    }
    .confirmationDialog(
      "这一天没有饮食记录", isPresented: $showEmptyDietConfirmation, titleVisibility: .visible
    ) {
      Button("确认当天没有摄入，标记完整") { model.confirmDiet(on: dietDate) }
      Button("继续补记", role: .cancel) {}
    } message: {
      Text("缺少记录不会自动按 0 kcal 处理；仅在确认没有摄入时使用此操作。")
    }
  }
  private var overview: some View {
    Section {
      if let value = model.result?.points.last(where: { $0.smoothedKilograms != nil })?
        .smoothedKilograms
      {
        LabeledContent("趋势体重", value: String(format: "%.1f kg", value))
      } else {
        Text("记录体重后开始建立趋势").foregroundStyle(.secondary)
      }
      LabeledContent("目标方向", value: model.input?.profile?.goalDirection?.trendTitle ?? "待设置")
      if model.needsProfileCompletion {
        Button("完善资料") { showProfile = true }
          .accessibilityIdentifier("trend.completeProfile")
      }
      if let rate = model.result?.weeklyChangePercent {
        LabeledContent("近 21 天变化速度", value: String(format: "%+.2f%% / 周", rate))
      }
      if let next = model.nextReview, next > model.now() {
        LabeledContent("下次复核", value: next.formatted(date: .abbreviated, time: .omitted))
      }
      if let hold = model.result?.holdReason {
        Text(hold.trendMessage).foregroundStyle(.secondary).accessibilityIdentifier("trend.hold")
      }
      if let input = model.input, TrendHistory.needsBaselineRebuild(input) {
        Text("身体资料已更新。观察满 7 天后，请核对并采用新的初始目标，重新建立基线。")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
  }
  private var weightChart: some View {
    Section("体重 · kg") {
      Picker("时间范围", selection: $rangeDays) {
        Text("4 周").tag(28)
        Text("12 周").tag(84)
        Text("全部").tag(0)
      }.pickerStyle(.segmented)
      if points.isEmpty {
        ContentUnavailableView(
          "还没有体重记录", systemImage: "chart.xyaxis.line",
          description: Text("可以手动记录，也可连接 Apple 健康读取已有记录。"))
      } else {
        Chart {
          ForEach(weights) { sample in
            PointMark(x: .value("日期", sample.measuredAt), y: .value("体重", sample.kilograms))
              .foregroundStyle(.secondary.opacity(0.5)).symbolSize(18)
              .accessibilityLabel(sample.source.kind == .manual ? "手动体重" : "Apple 健康体重")
              .accessibilityValue(String(format: "%.1f 公斤", sample.kilograms))
          }
          ForEach(Array(points.enumerated()), id: \.offset) { _, point in
            if let smooth = point.smoothedKilograms {
              LineMark(x: .value("日期", point.date), y: .value("平滑趋势", smooth))
                .foregroundStyle(Color.accentColor)
            }
          }
        }
        .chartYScale(domain: weightDomain)
        .frame(height: 200)
        .accessibilityIdentifier("trend.weightChart")
        Text("圆点为来源记录，曲线为平滑估计；异常代表值保留在记录中并提示复核。")
          .font(.caption).foregroundStyle(.secondary)
      }
      NavigationLink("体重记录与来源") { TrendWeightRecordsView(model: model) }
    }
  }
  private var dietSection: some View {
    Section("摄入完整度") {
      if let value = model.result?.facts.first(where: { $0.metric == "diet.completeDays" })?.value {
        LabeledContent("截至昨天的 14 天", value: "\(Int(value)) / 14 天已确认")
      }
      DatePicker("确认日期", selection: $dietDate, in: ...model.now(), displayedComponents: .date)
      let selected = model.input?.nutrition.first { $0.localDate == model.calendar.key(dietDate) }
      if selected?.isComplete == true {
        Label("所选日期已确认完整", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
      } else {
        Button("当天饮食已记完整") {
          if selected?.logIDs.isEmpty != false {
            showEmptyDietConfirmation = true
          } else {
            model.confirmDiet(on: dietDate)
          }
        }.accessibilityIdentifier("trend.confirmDiet")
        Text("编辑饮食记录后需要重新确认。未确认的日期不用于平均摄入。")
          .font(.caption).foregroundStyle(.secondary)
      }
      if let totals = selected?.totals { targetRows(totals, prefix: "已记录") }
      let nutrition =
        model.input?.nutrition.filter {
          model.calendar.date($0.localDate).map { $0 >= start } == true
        } ?? []
      if !nutrition.isEmpty {
        Chart(Array(nutrition.enumerated()), id: \.offset) { _, day in
          if let date = model.calendar.date(day.localDate) {
            BarMark(x: .value("日期", date), y: .value("已记录热量", day.totals.calories))
              .foregroundStyle(day.isComplete ? Color.accentColor : Color.secondary.opacity(0.4))
          }
        }
        .chartXAxis {
          AxisMarks(values: .automatic(desiredCount: 3)) { _ in
            AxisGridLine()
            AxisTick()
            AxisValueLabel(format: .dateTime.month().day())
          }
        }
        .frame(height: 120)
        Text("热量 · kcal。浅色为未确认完整的记录；空白日期表示未知。")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
  private var goalSection: some View {
    Section("营养目标") {
      Picker(
        "目标模式",
        selection: Binding(
          get: { model.input?.preferences.goalMode ?? .manual },
          set: {
            if $0 == .automatic { showAutomaticConfirmation = true } else { model.setMode($0) }
          })
      ) {
        Text("手动").tag(GoalMode.manual)
        Text("建议后采用").tag(GoalMode.suggested)
        Text("每周自动采用").tag(GoalMode.automatic)
      }.accessibilityIdentifier("trend.goalMode")
      if let current = model.input?.currentManualTargets {
        targetRows(current, prefix: "当前")
        if let latest = model.input.flatMap({
          TrendHistory.effective(at: $0.asOf, history: $0.goalHistory)
        }) {
          Text("生效日：\(latest.effectiveAt.formatted(date: .abbreviated, time: .omitted))")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      if let proposal = model.result?.proposal {
        targetRows(proposal.targets, prefix: "建议")
        if let previous = proposal.previousTargets {
          let adjustment =
            TrendNutrition.displayed(proposal.targets).calories
            - TrendNutrition.displayed(previous).calories
          Text(String(format: "热量调整 %+.0f kcal", adjustment))
        } else {
          Text("根据身体资料建立初始目标")
        }
        DisclosureGroup("建议依据") {
          ForEach(model.result?.facts.filter { proposal.reasonFactIDs.contains($0.id) } ?? []) {
            fact in
            if let value = fact.value {
              LabeledContent(
                fact.trendTitle, value: String(format: "%.1f %@", value, fact.unit.trendTitle))
            }
          }
        }
        let rebuilding = model.input.map { TrendHistory.needsBaselineRebuild($0) } ?? false
        if rebuilding {
          Text("这是新配置的初始估计，需要你确认；采用后至少观察 7 天再调整。")
            .font(.footnote).foregroundStyle(.secondary)
        }
        Button(rebuilding ? "采用新的初始目标" : "采用建议") { model.adopt(proposal.id) }
          .disabled(!model.canApplyGoals).accessibilityIdentifier("trend.adopt")
        Button("暂不采用，7 天后复核") {
          model.pause(until: model.calendar.adding(days: 7, to: model.now()))
        }
      }
      if model.input?.preferences.pausedUntil.map({ $0 > model.now() }) == true {
        Button("恢复建议复核") { model.pause(until: nil) }.accessibilityIdentifier("trend.resume")
      } else {
        Button("暂停调整 7 天") { model.pause(until: model.calendar.adding(days: 7, to: model.now())) }
          .accessibilityIdentifier("trend.pause")
      }
    }
  }
  private var historySection: some View {
    Section("目标历史") {
      let history = TrendHistory.ordered(model.input?.goalHistory ?? []).reversed()
      if history.isEmpty {
        Text("采用或手动保存后保留历史；当前旧目标不会被虚构成过去的目标。")
          .foregroundStyle(.secondary)
      }
      ForEach(Array(history)) { revision in
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text(revision.effectiveAt, style: .date)
            Spacer()
            Text(revision.reversesRevisionID == nil ? revision.origin.trendTitle : "撤销恢复")
              .font(.caption).foregroundStyle(.secondary)
          }
          targetRows(revision.targets, prefix: "")
          if TrendHistory.isReversed(revision, history: model.input?.goalHistory ?? []) {
            Text("已撤销").font(.caption).foregroundStyle(.secondary)
          } else if let input = model.input, TrendGoalWorkflow.canUndo(revision.id, input: input) {
            Button("撤销并暂停 7 天") { model.undo(revision.id) }
              .disabled(!model.canApplyGoals).accessibilityIdentifier("trend.undo")
            Text("恢复上次目标，暂停后仍按原设置复核。")
              .font(.caption).foregroundStyle(.secondary)
          } else if history.count == 1 && revision.origin != .manual {
            Text("这是首个目标，没有可恢复的旧值。可在手动目标中修改。")
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
        "碳水 \(Int(shown.carbohydrates)) g · 蛋白质 \(Int(shown.protein)) g · 脂肪 \(Int(shown.fat)) g"
      )
      .font(.subheadline).foregroundStyle(.secondary)
    }.accessibilityElement(children: .combine)
  }
}

extension GoalDirection {
  var trendTitle: String { self == .maintain ? "维持" : self == .lose ? "减脂" : "增肌" }
}
extension GoalRevisionOrigin {
  var trendTitle: String { self == .manual ? "手动" : self == .suggested ? "已采用建议" : "自动采用" }
}
extension TrendHoldReason {
  var trendMessage: String {
    switch self {
    case .missingProfile: return "补充身体资料后可生成初始建议，也可继续使用手动目标。"
    case .insufficientWeights: return "体重记录不足：需要至少 14 天跨度、8 个称重日，最近两周各至少 3 天。"
    case .incompleteDiet: return "最近 14 天至少需要 12 天确认饮食完整，暂时保留目标。"
    case .baselineBuilding: return "正在建立基线，目标或资料变更后至少观察 7 天。"
    case .manualMode: return "当前使用手动目标。可选择建议模式，由你决定是否采用。"
    case .paused: return "已暂停调整，当前目标保持不变。"
    case .safetyBoundary: return "当前身体条件或营养预算需要复核，请使用手动目标或专业方案。"
    case .requiresReview: return "请复核异常体重、身体资料或摄入与历史目标的差异，当前目标保持不变。"
    case .unchanged: return "近期变化在目标容差内，保持当前目标。"
    case .readFailed: return "体重读取失败，可重试或先记录手动体重。"
    }
  }
}
extension MetricFact {
  var trendTitle: String {
    switch metric {
    case "weight.smoothed": return "趋势体重"
    case "energy.initialEstimate": return "公式能量参考"
    case "weight.targetWeeklyChangePercent": return "目标速度"
    case "weight.weeklyChangePercent": return "近期速度"
    case "diet.completeDays": return "完整饮食日"
    case "diet.targetDifferencePercent": return "与历史目标摄入差异"
    default: return metric
    }
  }
}
extension MetricUnit {
  var trendTitle: String {
    switch self {
    case .kilograms: return "kg"
    case .kilocalories: return "kcal"
    case .percentPerWeek: return "%/周"
    case .percent: return "%"
    case .count: return "天"
    default: return rawValue
    }
  }
}
