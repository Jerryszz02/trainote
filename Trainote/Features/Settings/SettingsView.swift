import SwiftData
import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @State private var exportDocument: BackupDocument?
  @State private var showExporter = false
  @State private var showImporter = false
  @State private var importMessage: String?
  @State private var showImportMessage = false
  @State private var showRestoreConfirmation = false

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

        Section("本地备份") {
          Button("导出全部数据") { exportBackup() }
            .accessibilityIdentifier("backup.export")
          Button("恢复本地备份") { showImporter = true }
            .accessibilityIdentifier("backup.import")
          Text("备份文件包含训练、饮食和设置记录，只保存在你选择的位置；文件可能含有个人健康记录，请妥善保管。")
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
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \NutritionGoal.updatedAt, order: .reverse)
  private var goals: [NutritionGoal]

  @State private var calories = 2_000.0
  @State private var carbohydrates = 250.0
  @State private var protein = 150.0
  @State private var fat = 65.0
  @State private var loadedExistingGoal = false
  @State private var saved = false
  @State private var saveError: String?

  private var isValid: Bool {
    calories.isValidNonnegativeNumber && calories > 0
      && carbohydrates.isValidNonnegativeNumber
      && protein.isValidNonnegativeNumber
      && fat.isValidNonnegativeNumber
  }

  var body: some View {
    Form {
      Section("每日目标") {
        nutrientField("卡路里", value: $calories, unit: "kcal")
        nutrientField("碳水", value: $carbohydrates, unit: "g")
        nutrientField("蛋白质", value: $protein, unit: "g")
        nutrientField("脂肪", value: $fat, unit: "g")
      }

      Section {
        Text("目标由你手动设置。Trainote 不会根据身体数据自动生成饮食建议。")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("营养目标")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button(saved ? "已保存" : "保存", action: save)
          .disabled(!isValid)
          .accessibilityIdentifier("goal.save")
      }
    }
    .toolbar { NutritionKeyboardDoneToolbar() }
    .onChange(of: calories) { saved = false }
    .onChange(of: carbohydrates) { saved = false }
    .onChange(of: protein) { saved = false }
    .onChange(of: fat) { saved = false }
    .alert(
      "保存失败", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
    ) {
      Button("好", role: .cancel) {}
    } message: {
      Text(saveError ?? "")
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
        Text(unit).foregroundStyle(.secondary)
      }
    }
  }

  private func loadExistingGoalIfNeeded() {
    guard !loadedExistingGoal else { return }
    loadedExistingGoal = true
    guard let goal = goals.first else { return }
    calories = goal.calories
    carbohydrates = goal.carbohydrates
    protein = goal.protein
    fat = goal.fat
  }

  private func save() {
    guard isValid else { return }
    if let goal = goals.first {
      goal.calories = calories
      goal.carbohydrates = carbohydrates
      goal.protein = protein
      goal.fat = fat
      goal.updatedAt = .now
    } else {
      modelContext.insert(
        NutritionGoal(
          calories: calories,
          carbohydrates: carbohydrates,
          protein: protein,
          fat: fat
        )
      )
    }
    for duplicate in goals.dropFirst() {
      modelContext.delete(duplicate)
    }
    do {
      try modelContext.save()
      saved = true
    } catch {
      modelContext.rollback()
      saved = false
      saveError = error.localizedDescription
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
        Text("训练和饮食记录只保存在本机。Trainote 不上传内容，也不提供医疗或专业训练建议。")
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
    ScrollView {
      Text(
        "Trainote 隐私政策\n\n训练、饮食、常用食物、计划和营养目标只保存在本机。Trainote 不要求账号，不包含广告、分析、追踪或遥测，也不会主动上传你的内容。\n\n你导出的备份由你选择保存位置；备份可能包含个人记录，请自行妥善保管。删除记录或卸载 App 后，系统备份中的副本仍由你的设备和 Apple 账户设置管理。\n\nTrainote 只是手动记录工具，不提供医疗诊断或专业训练建议。"
      )
      .frame(maxWidth: .infinity, alignment: .leading).padding()
    }
    .navigationTitle("隐私政策").navigationBarTitleDisplayMode(.inline)
  }
}

struct SupportView: View {
  private let issuesURL = URL(string: "https://github.com/Jerryszz02/trainote/issues")!
  var body: some View {
    List {
      Section("本地备份") {
        Text(
          "在设置中选择“导出全部数据”，将 JSON 文件保存到安全位置。更换设备后选择“恢复本地备份”，先预览记录数量，再确认恢复。已有相同 ID 的记录会跳过，当前数据不会被删除。")
      }
      Section("反馈") { Link("在 GitHub 提交问题", destination: issuesURL) }
    }.navigationTitle("帮助与反馈").navigationBarTitleDisplayMode(.inline)
  }
}
