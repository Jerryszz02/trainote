import SwiftData
import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(HealthFeatureAccess.self) private var healthAccess
  @State private var exportDocument: BackupDocument?
  @State private var showExporter = false
  @State private var showImporter = false
  @State private var importMessage: L10n.Message?
  @State private var showImportMessage = false
  @State private var showRestoreConfirmation = false
  @State private var showHealthDeletion = false
  @State private var showReportDeletion = false

  var body: some View {
    NavigationStack {
      Form {
        Section(L10n.text("language.title")) {
          Picker(L10n.text("language.title"), selection: Binding(
            get: { LanguageSettings.shared.preference },
            set: { LanguageSettings.shared.preference = $0 }
          )) {
            ForEach(AppLanguage.allCases) { language in
              Text(language.title).tag(language)
            }
          }
          .accessibilityIdentifier("settings.language")
        }

        Section(L10n.text("settings.nutrition")) {
          NavigationLink(L10n.text("settings.dailyGoals")) {
            NutritionGoalEditor()
          }
        }

        Section(L10n.text("settings.units")) {
          LabeledContent(L10n.text("settings.weight"), value: L10n.text("settings.kilograms"))
          LabeledContent(L10n.text("settings.distance"), value: L10n.text("settings.kilometers"))
        }

        Section(L10n.text("settings.health")) {
          LabeledContent(L10n.text("settings.appleHealth"), value: healthAccess.healthConnectionLabel)
          if let detail = healthAccess.healthConnectionDetail {
            Text(detail).font(.footnote).foregroundStyle(.secondary)
          }
          Text(L10n.text("settings.healthPermissions"))
            .font(.footnote).foregroundStyle(.secondary)
            .accessibilityIdentifier("settings.healthPermissionHelp")
          Button(healthAccess.healthConnected ? L10n.text("settings.refreshHealth") : L10n.text("settings.connectHealth")) {
            Task { await healthAccess.connectHealth() }
          }
          .accessibilityIdentifier("settings.connectHealth")
          .disabled(healthAccess.isBusy || healthAccess.health == nil)
          Button(healthAccess.healthDeletionNeedsRetry ? L10n.text("settings.retryDisconnect") : L10n.text("settings.disconnect"), role: .destructive) {
            showHealthDeletion = true
          }
          .accessibilityIdentifier("settings.disconnectHealth")
          .disabled(healthAccess.isBusy)
          NavigationLink(L10n.text("settings.aiReports")) { AIConsentView() }
            .accessibilityIdentifier("settings.aiReports")
          if healthAccess.consent?.record(for: .aiReports)?.isGranted == true
            || healthAccess.aiRevocationNeedsRetry || healthAccess.reports.serverRevocationPending {
            Button(L10n.text("settings.revokeAI")) { Task { await healthAccess.revokeAI() } }
              .accessibilityIdentifier("settings.revokeAI")
              .disabled(healthAccess.isBusy)
          }
          Button(L10n.text("settings.deleteAI"), role: .destructive) { showReportDeletion = true }
            .accessibilityIdentifier("settings.deleteAIReports")
            .disabled(healthAccess.isBusy)
          NavigationLink(L10n.text("settings.methods")) { HealthHelpView() }
            .accessibilityIdentifier("settings.healthHelp")
          if let message = healthAccess.statusMessage {
            Text(message).font(.footnote).foregroundStyle(.secondary)
              .accessibilityIdentifier("settings.healthStatus")
          }
        }

        Section(L10n.text("settings.backup")) {
          Button(L10n.text("settings.export")) { exportBackup() }
            .accessibilityIdentifier("backup.export")
          Button(L10n.text("settings.restoreBackup")) { showImporter = true }
            .accessibilityIdentifier("backup.import")
          Text(L10n.text("settings.backupHelp"))
            .font(.footnote).foregroundStyle(.secondary)
        }

        Section(L10n.text("settings.about")) {
          NavigationLink(L10n.text("settings.sources")) {
            AboutView()
          }
        }
      }
      .navigationTitle(L10n.text("settings.title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("settings.done")) { dismiss() }
        }
      }
      .fileExporter(
        isPresented: $showExporter, document: exportDocument, contentType: .json,
        defaultFilename: "trainote-backup.json",
        onCompletion: { result in
          if case .failure(let error) = result {
            importMessage = L10n.Message("settings.exportError", error.localizedDescription)
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
          importMessage = L10n.Message("settings.openError", error.localizedDescription)
          showImportMessage = true
        }
      }
      .alert(L10n.text("settings.backupAlert"), isPresented: $showImportMessage) {
        Button(L10n.text("settings.ok"), role: .cancel) {}
      } message: {
        Text(importMessage?.text ?? "")
      }
      .confirmationDialog(L10n.text("settings.restoreTitle"), isPresented: $showRestoreConfirmation, titleVisibility: .visible)
      {
        Button(L10n.text("settings.restore")) { commitRestore() }
        Button(L10n.text("settings.cancel"), role: .cancel) { pendingRestore = nil }
      } message: {
        Text(importMessage?.text ?? "")
      }
      .confirmationDialog(L10n.text("settings.disconnectQuestion"), isPresented: $showHealthDeletion, titleVisibility: .visible) {
        Button(L10n.text("settings.disconnectConfirm"), role: .destructive) {
          #if DEBUG
            HealthUITestTrace.record("disconnect.confirmationAction")
          #endif
          Task { await healthAccess.disconnectHealth() }
        }
        Button(L10n.text("settings.cancel"), role: .cancel) {}
      } message: {
        Text(L10n.text("settings.disconnectHelp"))
      }
      .confirmationDialog(L10n.text("settings.deleteQuestion"), isPresented: $showReportDeletion, titleVisibility: .visible) {
        Button(L10n.text("settings.deleteReports"), role: .destructive) { healthAccess.deleteReports() }
        Button(L10n.text("settings.cancel"), role: .cancel) {}
      } message: { Text(L10n.text("settings.deleteHelp")) }
      .healthAccessError(healthAccess)
    }
  }

  private func exportBackup() {
    do {
      exportDocument = BackupDocument(data: try BackupArchiveService.export(context: modelContext))
      showExporter = true
    } catch {
      importMessage = L10n.Message("settings.exportError", error.localizedDescription)
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
      importMessage = L10n.Message("settings.restorePreview", archive.counts.total)
      // Decode once above for a useful preview, then restore after explicit confirmation.
      pendingRestore = values
      showRestoreConfirmation = true
    } catch {
      importMessage = L10n.Message("settings.readError", error.localizedDescription)
      showImportMessage = true
    }
  }

  private func commitRestore() {
    guard let data = pendingRestore else { return }
    do {
      try modelContext.save()
      let result = try BackupArchiveService.importData(data, into: modelContext.container)
      importMessage = L10n.Message("settings.restoreResult", result.inserted, result.skipped)
    } catch { importMessage = L10n.Message("settings.restoreError", error.localizedDescription) }
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
  @State private var saveError: L10n.Message?
  @State private var staleTarget = false

  private var isValid: Bool {
    editing.targets.calories.isValidNonnegativeNumber && editing.targets.calories > 0
      && editing.targets.carbohydrates.isValidNonnegativeNumber
      && editing.targets.protein.isValidNonnegativeNumber
      && editing.targets.fat.isValidNonnegativeNumber
  }

  var body: some View {
    Form {
      Section(L10n.text("settings.dailyTargets")) {
        nutrientField(L10n.text("settings.calories"), value: $editing.targets.calories, unit: "kcal", identifier: "goal.卡路里")
        nutrientField(L10n.text("settings.carbs"), value: $editing.targets.carbohydrates, unit: "g", identifier: "goal.碳水")
        nutrientField(L10n.text("settings.protein"), value: $editing.targets.protein, unit: "g", identifier: "goal.蛋白质")
        nutrientField(L10n.text("settings.fat"), value: $editing.targets.fat, unit: "g", identifier: "goal.脂肪")
      }

      Section {
        Text(L10n.text("settings.goalHelp"))
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle(L10n.text("settings.goals"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button(saved ? L10n.text("settings.saved") : L10n.text("settings.save"), action: save)
          .disabled(!isValid || saved || editing.expectedState == nil)
          .accessibilityIdentifier("goal.save")
      }
    }
    .toolbar { NutritionKeyboardDoneToolbar() }
    .onChange(of: editing.targets) { saved = false }
    .alert(
      L10n.text("settings.saveFailed"), isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
    ) {
      Button(L10n.text("settings.ok"), role: .cancel) {}
    } message: {
      Text(saveError?.text ?? "")
    }
    .alert(L10n.text("settings.staleGoal"), isPresented: $staleTarget) {
      Button(L10n.text("settings.reloadGoal")) { loadLatestGoal() }
      Button(L10n.text("settings.keepDraft"), role: .cancel) {}
    } message: {
      Text(L10n.text("settings.staleHelp"))
    }
    .safeAreaInset(edge: .bottom) {
      if loadedExistingGoal && editing.expectedState == nil {
        Button(L10n.text("settings.reloadToEdit"), action: loadLatestGoal)
          .buttonStyle(.borderedProminent).padding()
      }
    }
    .task { loadExistingGoalIfNeeded() }
  }

  private func nutrientField(_ title: String, value: Binding<Double>, unit: String, identifier: String) -> some View {
    LabeledContent(title) {
      HStack(spacing: 6) {
        StableNumberField("0", value: value, format: .number.precision(.fractionLength(0...1)).locale(L10n.locale))
          .keyboardType(.decimalPad)
          .submitLabel(.done)
          .multilineTextAlignment(.trailing)
          .frame(minWidth: 80)
          .accessibilityIdentifier(identifier)
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
      saveError = L10n.Message("settings.loadGoalError")
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
      saveError = L10n.Message("settings.saveGoalError")
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
        LabeledContent(L10n.text("settings.version"), value: versionText)
        Text(L10n.text("settings.aboutPrivacy"))
      }

      Section(L10n.text("settings.privacySupport")) {
        NavigationLink(L10n.text("settings.privacy")) { PrivacyView() }
          .accessibilityIdentifier("about.privacy")
        NavigationLink(L10n.text("settings.support")) { SupportView() }
          .accessibilityIdentifier("about.support")
      }

      Section(L10n.text("settings.exerciseData")) {
        LabeledContent(L10n.text("settings.exerciseCount"), value: "\(catalog.items.count)")
        if let source = catalog.source {
          LabeledContent(L10n.text("settings.datasetCommit"), value: String(source.commit.prefix(8)))
          Text(source.license)
            .font(.footnote)
          if let url = URL(string: source.repository) {
            Link(L10n.text("settings.datasetRepository"), destination: url)
          }
        }
        Text(L10n.text("settings.datasetLicense"))
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle(L10n.text("settings.about"))
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
      Section(L10n.text("settings.healthAnalysis")) {
        NavigationLink(L10n.text("settings.healthHelp")) { HealthHelpView() }
      }
      Section(L10n.text("settings.backup")) {
        Text(
          L10n.text("settings.restoreInstructions"))
      }
      Section(L10n.text("settings.feedback")) { Link(L10n.text("settings.githubIssue"), destination: issuesURL) }
    }.navigationTitle(L10n.text("settings.support")).navigationBarTitleDisplayMode(.inline)
  }
}
