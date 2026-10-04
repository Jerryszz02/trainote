import SwiftData
import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(HealthFeatureAccess.self) private var healthAccess
  @State private var exportDocument: BackupDocument?
  @State private var showExporter = false
  @State private var showImporter = false
  @State private var importMessage: String?
  @State private var showImportMessage = false
  @State private var showRestoreConfirmation = false
  @State private var showHealthDeletion = false
  @State private var showReportDeletion = false

  var body: some View {
    NavigationStack {
      Form {
        Section("饮食管理") {
          NavigationLink("每日营养目标") {
            NutritionGoalEditor()
          }
        }

        Section("单位") {
          LabeledContent("重量", value: "公斤 (kg)")
          LabeledContent("距离", value: "公里 (km)")
        }

        Section("健康与分析") {
          LabeledContent("Apple 健康", value: healthAccess.healthConnectionLabel)
          if let detail = healthAccess.healthConnectionDetail {
            Text(detail).font(.footnote).foregroundStyle(.secondary)
          }
          Text("管理读取权限：“健康”App → 摘要 → 头像 → App → Trainote。")
            .font(.footnote).foregroundStyle(.secondary)
            .accessibilityIdentifier("settings.healthPermissionHelp")
          Button(healthAccess.healthConnected ? "刷新健康读取" : "连接 Apple 健康") {
            Task { await healthAccess.connectHealth() }
          }
          .accessibilityIdentifier("settings.connectHealth")
          .disabled(healthAccess.isBusy || healthAccess.health == nil)
          Button(healthAccess.healthDeletionNeedsRetry ? "重试断开并删除健康导入数据" : "断开并删除健康导入数据", role: .destructive) {
            showHealthDeletion = true
          }
          .accessibilityIdentifier("settings.disconnectHealth")
          .disabled(healthAccess.isBusy)
          NavigationLink("AI 报告") { AIConsentView() }
            .accessibilityIdentifier("settings.aiReports")
          if healthAccess.consent?.record(for: .aiReports)?.isGranted == true
            || healthAccess.aiRevocationNeedsRetry || healthAccess.reports.serverRevocationPending {
            Button("关闭 AI / 重试撤回") { Task { await healthAccess.revokeAI() } }
              .accessibilityIdentifier("settings.revokeAI")
              .disabled(healthAccess.isBusy)
          }
          Button("删除本机 AI 报告", role: .destructive) { showReportDeletion = true }
            .accessibilityIdentifier("settings.deleteAIReports")
            .disabled(healthAccess.isBusy)
          NavigationLink("方法、隐私与数据使用") { HealthHelpView() }
            .accessibilityIdentifier("settings.healthHelp")
          if let message = healthAccess.statusMessage {
            Text(message).font(.footnote).foregroundStyle(.secondary)
              .accessibilityIdentifier("settings.healthStatus")
          }
        }

        Section("本地备份") {
          Button("导出全部数据") { exportBackup() }
            .accessibilityIdentifier("backup.export")
          Button("恢复本地备份") { showImporter = true }
            .accessibilityIdentifier("backup.import")
          Text("导出 v2，支持恢复 v1 / v2；旧版 App 不保证能读 v2。包含手动健康资料、目标历史、训练和饮食；不包含健康导入缓存、授权、设备凭据或派生报告。备份只保存在你选择的位置，请妥善保管。")
            .font(.footnote).foregroundStyle(.secondary)
        }

        Section("关于") {
          NavigationLink("Trainote 与数据来源") {
            AboutView()
          }
        }
      }
      .navigationTitle("设置")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("完成") { dismiss() }
        }
      }
      .fileExporter(
        isPresented: $showExporter, document: exportDocument, contentType: .json,
        defaultFilename: "trainote-backup.json",
        onCompletion: { result in
          if case .failure(let error) = result {
            importMessage = "导出失败：\(error.localizedDescription)"
            showImportMessage = true
          }
        }
      )
      .fileImporter(
        isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false
      ) { result in
        switch result {
        case .success(let urls): if let url = urls.first { restore(from: url) }
        case .failure(let error):
          importMessage = "无法打开备份：\(error.localizedDescription)"
          showImportMessage = true
        }
      }
      .alert("备份", isPresented: $showImportMessage) {
        Button("好", role: .cancel) {}
      } message: {
        Text(importMessage ?? "")
      }
      .confirmationDialog("恢复备份", isPresented: $showRestoreConfirmation, titleVisibility: .visible)
      {
        Button("恢复") { commitRestore() }
        Button("取消", role: .cancel) { pendingRestore = nil }
      } message: {
        Text(importMessage ?? "")
      }
      .confirmationDialog("断开并删除健康导入数据？", isPresented: $showHealthDeletion, titleVisibility: .visible) {
        Button("断开并删除", role: .destructive) {
          #if DEBUG
            HealthUITestTrace.record("disconnect.confirmationAction")
          #endif
          Task { await healthAccess.disconnectHealth() }
        }
        Button("取消", role: .cancel) {}
      } message: {
        Text("停止同步并清除导入缓存、锚点和相关报告；保留手动记录，不改动 Apple 健康中的原始数据。")
      }
      .confirmationDialog("删除本机 AI 报告？", isPresented: $showReportDeletion, titleVisibility: .visible) {
        Button("删除报告", role: .destructive) { healthAccess.deleteReports() }
        Button("取消", role: .cancel) {}
      } message: { Text("删除本机报告缓存，不删除训练、饮食或健康记录。") }
      .healthAccessError(healthAccess)
    }
  }

  private func exportBackup() {
    do {
      exportDocument = BackupDocument(data: try BackupArchiveService.export(context: modelContext))
      showExporter = true
    } catch {
      importMessage = "导出失败：\(error.localizedDescription)"
      showImportMessage = true
    }
  }

  private func restore(from url: URL) {
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size <= BackupArchive.maxBytes else { throw BackupArchiveError.tooLarge }
      let values = try Data(contentsOf: url, options: [.mappedIfSafe])
      guard values.count <= BackupArchive.maxBytes else { throw BackupArchiveError.tooLarge }
      let archive = try BackupArchiveService.decode(values)
      importMessage = "将检查并添加 \(archive.counts.total) 条记录；已有相同 ID 的记录会跳过，不会删除当前数据。确定恢复吗？"
      // Decode once above for a useful preview, then restore after explicit confirmation.
      pendingRestore = values
      showRestoreConfirmation = true
    } catch {
      importMessage = "无法读取备份：\(error.localizedDescription)"
      showImportMessage = true
    }
  }

  private func commitRestore() {
    guard let data = pendingRestore else { return }
    do {
      try modelContext.save()
      let result = try BackupArchiveService.importData(data, into: modelContext.container)
      importMessage = "恢复完成：新增 \(result.inserted) 条，跳过 \(result.skipped) 条。"
    } catch { importMessage = "恢复失败：\(error.localizedDescription)" }
    pendingRestore = nil
    showImportMessage = true
  }

  @State private var pendingRestore: Data?
}

struct NutritionGoalEditor: View {
  @Environment(HealthFoundation.self) private var foundation
  @State private var editing = ManualNutritionGoalEditing()
  @State private var loadedExistingGoal = false
  @State private var saved = false
  @State private var saveError: String?
  @State private var staleTarget = false

  private var isValid: Bool {
    editing.targets.calories.isValidNonnegativeNumber && editing.targets.calories > 0
      && editing.targets.carbohydrates.isValidNonnegativeNumber
      && editing.targets.protein.isValidNonnegativeNumber
      && editing.targets.fat.isValidNonnegativeNumber
  }

  var body: some View {
    Form {
      Section("每日目标") {
        nutrientField("卡路里", value: $editing.targets.calories, unit: "kcal")
        nutrientField("碳水", value: $editing.targets.carbohydrates, unit: "g")
        nutrientField("蛋白质", value: $editing.targets.protein, unit: "g")
        nutrientField("脂肪", value: $editing.targets.fat, unit: "g")
      }

      Section {
        Text("在这里保存手动目标，保留此前目标历史。趋势页的自动采用仅在你主动开启后运行；不会因为升级而无声改变旧目标。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("营养目标")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button(saved ? "已保存" : "保存", action: save)
          .disabled(!isValid || saved || editing.expectedState == nil)
          .accessibilityIdentifier("goal.save")
      }
    }
    .toolbar { NutritionKeyboardDoneToolbar() }
    .onChange(of: editing.targets) { saved = false }
    .alert(
      "保存失败", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
    ) {
      Button("好", role: .cancel) {}
    } message: {
      Text(saveError ?? "")
    }
    .alert("目标已在别处更新", isPresented: $staleTarget) {
      Button("载入最新目标") { loadLatestGoal() }
      Button("保留草稿", role: .cancel) {}
    } message: {
      Text("本次修改尚未保存。载入最新目标后请重新检查并点击保存，避免覆盖新的目标。")
    }
    .safeAreaInset(edge: .bottom) {
      if loadedExistingGoal && editing.expectedState == nil {
        Button("载入最新目标再编辑", action: loadLatestGoal)
          .buttonStyle(.borderedProminent).padding()
      }
    }
    .task { loadExistingGoalIfNeeded() }
  }

  private func nutrientField(_ title: String, value: Binding<Double>, unit: String) -> some View {
    LabeledContent(title) {
      HStack(spacing: 6) {
        TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
          .keyboardType(.decimalPad)
          .submitLabel(.done)
          .multilineTextAlignment(.trailing)
          .frame(minWidth: 80)
          .accessibilityIdentifier("goal.\(title)")
        Text(unit).foregroundStyle(.secondary)
      }
    }
  }

  private func loadExistingGoalIfNeeded() {
    guard !loadedExistingGoal else { return }
    loadedExistingGoal = true
    loadLatestGoal()
  }

  private func loadLatestGoal() {
    do {
      try editing.load(from: foundation.repository)
      saved = false
      saveError = nil
    } catch {
      saveError = "未能读取当前目标，请重试。"
    }
  }

  private func save() {
    guard isValid else { return }
    do {
      try editing.save(to: foundation.repository)
      saved = true
    } catch GoalRevisionConflict.staleState {
      saved = false
      staleTarget = true
    } catch {
      saved = false
      saveError = "目标和历史均未改变，请重试。若目标日期异常，请检查设备时间或重新载入目标。"
    }
  }
}

struct AboutView: View {
  @Environment(ExerciseCatalog.self) private var catalog

  private var versionText: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    return [version, build.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
  }

  var body: some View {
    List {
      Section("Trainote") {
        LabeledContent("版本", value: versionText)
        Text("训练和饮食记录保存在本机。Apple 健康与 AI 报告分别选择；未配置真实 AI 服务时不会发送记录。分析是估计，不提供医疗诊断。")
      }

      Section("隐私与支持") {
        NavigationLink("隐私政策") { PrivacyView() }
          .accessibilityIdentifier("about.privacy")
        NavigationLink("帮助与反馈") { SupportView() }
          .accessibilityIdentifier("about.support")
      }

      Section("动作数据") {
        LabeledContent("动作数量", value: "\(catalog.items.count)")
        if let source = catalog.source {
          LabeledContent("固定提交", value: String(source.commit.prefix(8)))
          Text(source.license)
            .font(.footnote)
          if let url = URL(string: source.repository) {
            Link("打开数据集仓库", destination: url)
          }
        }
        Text("仅使用 MIT 许可覆盖的动作元数据和说明文字。Gym visual 图片与 GIF 未包含在 App 中。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("关于")
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct PrivacyView: View {
  var body: some View {
    HealthHelpView()
  }
}

struct SupportView: View {
  private let issuesURL = URL(string: "https://github.com/Jerryszz02/trainote/issues")!
  var body: some View {
    List {
      Section("健康分析") {
        NavigationLink("方法、权限、撤回和数据使用") { HealthHelpView() }
      }
      Section("本地备份") {
        Text(
          "在设置中选择“导出全部数据”，将 JSON 文件保存到安全位置。更换设备后选择“恢复本地备份”，先预览记录数量，再确认恢复。已有相同 ID 的记录会跳过，当前数据不会被删除。")
      }
      Section("反馈") { Link("在 GitHub 提交问题", destination: issuesURL) }
    }.navigationTitle("帮助与反馈").navigationBarTitleDisplayMode(.inline)
  }
}
