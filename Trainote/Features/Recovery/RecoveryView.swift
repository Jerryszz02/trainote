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
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if let error {
          ContentUnavailableView(
            "暂时无法更新分析", systemImage: "arrow.clockwise",
            description: Text(error))
          Button("重试") { reload() }
        } else if let result {
          VStack(alignment: .leading, spacing: 8) {
            Text("恢复指数").font(.title2.bold())
            Text("选择肌群查看最近负荷与体感").foregroundStyle(.secondary)
          }
          BodyMapView(presentation: result.bodyMapPresentation(selected: selected)) { muscle in
            selected = muscle
          }
          if let muscle = result.muscles.first(where: { $0.muscleID == selected }) {
            RecoveryMuscleDetail(
              muscle: muscle, result: result, onFeedback: { openCheckIn(muscle.muscleID) },
              onShowMethods: onShowMethods)
          }
          RecoverySystemicCard(result: result)
          if healthReadFailed {
            Text("健康数据暂时无法读取，当前显示本地记录。").font(.caption).foregroundStyle(.secondary)
          }
          if showPrompt {
            HStack {
              VStack(alignment: .leading) {
                Text("今天感觉如何？").font(.headline)
                Text("十秒补充体感，也可以跳过。").font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Button("填写") { openCheckIn() }
              Button("跳过") { showPrompt = false }
            }
          }
          Button("记录或修改今日体感") { openCheckIn() }
            .accessibilityIdentifier("recovery.checkIn.open")
          if let resetCalibration {
            Button("重置个体校准") { confirmingReset = true }
              .confirmationDialog(
                "从现在重新积累校准记录？", isPresented: $confirmingReset, titleVisibility: .visible
              ) {
                Button("重置校准") {
                  resetCalibration()
                  reload()
                }
                Button("取消", role: .cancel) {}
              } message: {
                Text("训练和体感历史会保留，恢复指数先使用基础参数。")
              }
          }
          if let onShowMethods { Button("计算方法与数据使用", action: onShowMethods) }
        } else {
          ProgressView("正在读取本地记录")
        }
      }.padding()
    }
    .navigationTitle("恢复分析")
    .accessibilityIdentifier("recovery.screen")
    .onAppear { reload() }
    .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
    .refreshable { reload() }
    .sheet(item: $checkInDraft, onDismiss: { reload() }) { draft in
      RecoveryCheckInView(repository: repository, suggestedMuscles: suggestedMuscles, draft: draft)
    }
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
      self.error = "读取或计算失败。原有训练记录仍保留，可稍后重试。"
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
      if muscle.hasPain { Label("已标记疼痛：相关训练暂不列入建议", systemImage: "exclamationmark.triangle") }
      if muscle.hasMovementLimitation {
        Label("已标记活动受限：相关训练暂不列入建议", systemImage: "exclamationmark.triangle")
      }
      if let date = muscle.lastTrainedAt {
        LabeledContent("上次训练", value: date.formatted(date: .abbreviated, time: .shortened))
      }
      if let fact = result.facts.first(where: {
        $0.id == "recovery.\(muscle.muscleID.rawValue).lastLoad"
      }), let load = fact.value {
        LabeledContent("最近一次加权工作组", value: load.formatted(.number.precision(.fractionLength(1))))
      }
      ForEach(muscle.influences, id: \.code) { influence in
        Text(RecoveryCopy.influence(influence.code)).font(.subheadline).foregroundStyle(.secondary)
      }
      if let coverage = muscle.coverage.first {
        Text("近 \(coverage.expectedDays) 天：\(coverage.observedDays) 天有该肌群可用记录")
          .font(.caption).foregroundStyle(.secondary)
      }
      Button("更新这块肌群的体感", action: onFeedback)
      if let onShowMethods { Button("分数说明", action: onShowMethods) }
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
      Text("全身状态").font(.headline)
      Text(RecoveryCopy.systemic(result.systemicState))
      if let feeling = result.facts.first(where: { $0.id == "recovery.feeling" })?.value {
        LabeledContent("今日体感", value: feeling == 2 ? "好" : (feeling == 1 ? "一般" : "疲惫"))
      }
      if let sleep = result.facts.first(where: { $0.id == "recovery.sleepFeeling" })?.value {
        LabeledContent("主观睡眠", value: sleep == 2 ? "好" : (sleep == 1 ? "一般" : "较差"))
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
              Text("个人基线：\(RecoveryCopy.value(value, unit: baseline.unit))").font(.caption)
                .foregroundStyle(.secondary)
            } else {
              Text("正在建立个人基线").font(.caption).foregroundStyle(.secondary)
            }
          }
          if let deviation = result.facts.first(where: {
            $0.id == "recovery.systemic.\(metric).deviationPercent"
          })?.value {
            Text("相对基线：\(deviation.formatted(.number.precision(.fractionLength(0))))%").font(
              .caption
            ).foregroundStyle(.secondary)
          }
        }
      }
      if result.facts.contains(where: { $0.id == "recovery.systemic.externalWorkout" }) {
        Text("Apple 健康的外部训练仅作活动参考，肌群负荷需逐动作记录。")
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
    case .ready: "状态较好"
    case .moderate: "适度安排"
    case .low: "优先恢复"
    case .limited: "训练受限"
    case .unknown: "待建立记录"
    }
  }
  static func systemic(_ state: RecoveryState) -> String {
    switch state {
    case .ready: "当前体感或个人基线未提示持续变化"
    case .moderate: "留意体感与近期变化"
    case .low, .limited: "连续变化伴随疲惫，今天适当减量"
    case .unknown: "尚无足够的全身状态记录"
    }
  }
  static func influence(_ code: String) -> String {
    switch code {
    case "recordedLoad": "根据已记录工作组、RIR 和经过时间估计。"
    case "unknownRIRPrior": "部分组未填 RIR，采用默认努力程度。"
    case "historicalRolePrior": "历史组类型未区分，暂按工作组计入。"
    case "unallocatedExercise": "存在待核查动作、未支持的记录方式或未逐动作记录的外部力量训练，暂不计算完整准备度。"
    case "significantSoreness": "明显酸痛：优先减少相关训练量。"
    case "mildSoreness": "已记录轻微酸痛，结合本次表现安排训练。"
    case "excludeTraining": "疼痛或活动受限独立于分数，需先更新体感。"
    case "calibratedCandidate": "个体参数通过时间留出比较后保守调整。"
    default: "近期可用记录不足；完成并记录训练后会更新。"
    }
  }
  static func metric(_ metric: String) -> String {
    switch metric {
    case "sleep.duration": "最近睡眠"
    case "restingHeartRate": "静息心率"
    default: "HRV（SDNN）"
    }
  }
  static func value(_ value: Double, unit: MetricUnit) -> String {
    if unit == .seconds {
      return "\((value / 3600).formatted(.number.precision(.fractionLength(1)))) 小时"
    }
    return
      "\(value.formatted(.number.precision(.fractionLength(0)))) \(unit == .milliseconds ? "ms" : "次/分")"
  }
}
