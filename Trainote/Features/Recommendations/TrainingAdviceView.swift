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
        Section("进行中的训练") {
          Text("你已有一条进行中的训练。完成或结束它后，才能按建议创建新训练。")
            .foregroundStyle(.secondary)
          Button("继续进行中的训练") { onStartWorkout(activeWorkout) }
            .accessibilityIdentifier("advice.continueWorkout")
        }
      }
      Section("本次训练") {
        Picker(
          "选择模板",
          selection: Binding(
            get: { controller.selectedRoutineID },
            set: { controller.selectedRoutineID = $0 }
          )
        ) {
          Text("尚未选择").tag(Optional<UUID>.none)
          ForEach(controller.routines) { routine in
            Text(routine.name).tag(Optional(routine.id))
          }
        }
        .accessibilityIdentifier("advice.selectedRoutine")
        Text("这里只选择本次想用的模板，不会自动建立长期训练计划。")
          .font(.caption).foregroundStyle(.secondary)
        if let selected = controller.selectedRoutineID {
          ForEach(controller.routines.filter { $0.id != selected }) { routine in
            Toggle(
              "备选：\(routine.name)",
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
      Section("可训练日（可选）") {
        if controller.availableWeekdays == nil {
          Button("填写可训练日") { controller.availableWeekdays = [] }
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
          Button("清除日期选择") { controller.availableWeekdays = nil }
            .accessibilityIdentifier("advice.schedule.clear")
        }
      }
      Section {
        Button("查看今日建议") { controller.refresh() }
          .accessibilityIdentifier("advice.refresh")
      }
      if let message = controller.errorMessage {
        Section { Text(message).foregroundStyle(.secondary) }
      } else if let evaluation = controller.evaluation {
        Section("今日建议") {
          if !evaluation.blockedMuscles.isEmpty {
            Label(
              "另有疼痛或活动受限记录：\(evaluation.blockedMuscles.map(\.displayName).joined(separator: "、"))。涉及这些肌群的训练仍受限制。",
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
          Section("选择本次参数") {
            ForEach(candidate.allowedParameters, id: \.name) { allowed in
              Stepper(
                "\(allowed.name == "minimumRIR" ? "至少保留余力" : "保留工作组")：\(Int(parameterValues[allowed.name] ?? allowed.minimum))\(allowed.unit == .percent ? "%" : " 次")",
                value: Binding(
                  get: { parameterValues[allowed.name] ?? allowed.minimum },
                  set: { parameterValues[allowed.name] = $0 }),
                in: allowed.minimum...allowed.maximum,
                step: allowed.name == "minimumRIR" ? 1 : 5
              )
              .accessibilityIdentifier("advice.parameter.\(allowed.name)")
            }
            Button("按这些参数继续") { pendingActionID = parameterActionID }
              .accessibilityIdentifier("advice.parameters.confirm")
          }
        }
        Section {
          Text("建议基于当前记录和所选模板。开始前会重新读取记录；如果体感、限制或模板改变，需要重新查看建议。")
            .font(.caption).foregroundStyle(.secondary)
        }
      } else {
        Section {
          Text("选好本次模板后查看建议；恢复或饮食证据不足时会提示复核。")
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("训练建议")
    .accessibilityIdentifier("advice.screen")
    .onAppear { controller.loadRoutines() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { controller.loadRoutines() }
    }
    .confirmationDialog(
      "按这条建议开始训练？",
      isPresented: Binding(
        get: { pendingActionID != nil },
        set: { if !$0 { pendingActionID = nil } }),
      titleVisibility: .visible
    ) {
      Button("确认并开始") { adoptPending() }
      Button("取消", role: .cancel) { pendingActionID = nil }
    } message: {
      Text("会新建一条进行中的训练记录；原模板和历史记录保持不变。")
    }
    .alert(
      "无法开始训练",
      isPresented: Binding(
        get: { actionError != nil }, set: { if !$0 { actionError = nil } }
      )
    ) {
      Button("知道了", role: .cancel) {}
    } message: {
      Text(actionError ?? "请刷新后重试。")
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
          Button("查看或修改今日体感") { openCheckIn() }
            .accessibilityIdentifier("advice.editCheckIn")
        }
      }
      if let plan = controller.evaluation?.plansByAction[candidate.actionID],
        let routine = controller.routines.first(where: { $0.id == plan.id })
      {
        Text("模板：\(routine.name)").font(.caption).foregroundStyle(.secondary)
      }
      if candidate.action == .reviewNutrition, let onOpenNutrition {
        Button("查看饮食趋势", action: onOpenNutrition)
          .accessibilityIdentifier("advice.openNutrition")
      } else if candidate.action == .choosePlan, let onOpenRecovery {
        Button("查看恢复记录", action: onOpenRecovery)
          .accessibilityIdentifier("advice.openRecovery")
      } else if isStartable(candidate) && controller.activeWorkout == nil {
        Button("选择参数并开始") {
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
      actionError = "已有进行中的训练。请点击“继续进行中的训练”返回这条记录。"
    } catch TrainingAdviceAdoptionError.templateChanged {
      actionError = "所选模板或备选模板已变化。请重新查看今日建议。"
    } catch TrainingAdviceAdoptionError.recordsChanged {
      actionError = "体感、日程或训练记录已变化。请重新查看今日建议。"
    } catch {
      actionError = "暂时无法保存训练，请检查本地记录后重试。"
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
      actionError = "暂时无法读取今日体感，请稍后重试。"
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
    case .unavailableToday: "你填写的可训练日不包括今天。"
    case .noWeeklyTrainingDays: "个人资料中的每周训练天数为 0。"
    case .tiredCheckIn: "你今天记录了整体疲惫，因此先安排休息。"
    case .systemicLimited: "全身恢复状态显示训练受限。"
    case .systemicLow: "全身恢复状态显示优先恢复。"
    case .restrictedMuscles(let muscles):
      action == .swapTrainingDay
        ? "原选模板涉及\(muscles.map(\.displayName).joined(separator: "、"))，这些肌群已标记疼痛或活动受限，因此改用备选模板。"
        : "\(muscles.map(\.displayName).joined(separator: "、"))已记录疼痛或活动受限，所选模板涉及这些肌群。"
    case .unverifiedMappingWithRestriction:
      "有肌群记录了疼痛或活动受限，而所选模板的动作映射尚未完整核对。"
    case .significantSoreness: "相关肌群今天记录了明显酸痛。"
    case .recentWorkingSets(let count): "相关肌群近 24 小时完成了 \(count) 组工作组。"
    case .reducedReadiness: "所选肌群的恢复状态尚未达到直接沿用模板的条件。"
    case .insufficientCoverage: "所选模板的动作映射或相关肌群恢复记录尚不足以确认。"
    case .noSelectedPlan: "尚未选择本次训练模板。"
    case .ready: "所选肌群当前记录未触发减量或避开训练的规则。"
    case .nutritionDifference: "饮食记录与目标存在需复核的差异。"
    }
  }

  private func weekdayName(_ day: Int) -> String {
    ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][day - 1]
  }

  private func title(for action: RecommendationAction) -> String {
    switch action {
    case .keepPlan: "按所选模板训练"
    case .reduceSets: "减少工作组"
    case .increaseRIR: "保留更多余力"
    case .swapTrainingDay: "改用备选模板"
    case .rest: "安排休息"
    case .lightActivity: "可选轻活动"
    case .choosePlan: "先复核模板与恢复记录"
    case .reviewNutrition: "复核饮食目标与记录"
    }
  }

  private func explanation(for action: RecommendationAction) -> String {
    switch action {
    case .keepPlan: "当前记录允许使用所选模板；仍请按实际感受调整。"
    case .reduceSets: "工作组保留在建议范围内，不增加负重。"
    case .increaseRIR: "目标 RIR 是训练提示，完成后再填写实际 RIR。"
    case .swapTrainingDay: "仅使用你显式选定、已审核映射且不涉及受限肌群的备选模板。"
    case .rest: "当前记录提示今天先休息，不会创建训练。"
    case .lightActivity: "可按体感选择轻活动；这里不规定强度或创建训练。"
    case .choosePlan: "缺少可确认的训练或恢复证据；先检查模板、记录和体感。"
    case .reviewNutrition: "饮食差异单独复核，不用于降低肌群恢复分数。"
    }
  }
}
