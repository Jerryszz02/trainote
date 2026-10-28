import SwiftData
import SwiftUI

struct FirstUseNoticeView: View {
  @Environment(FirstUseNoticeStore.self) private var notice
  @Environment(HealthFeatureAccess.self) private var healthAccess
  @Environment(\.modelContext) private var modelContext
  var readOnly = false
  @State private var declined = false
  @State private var message: String?
  @State private var exportDocument: BackupDocument?
  @State private var showExporter = false
  @State private var showDeleteAll = false
  @State private var showDeleteHealth = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Picker(L10n.text("language.title"), selection: Binding(
          get: { LanguageSettings.shared.language },
          set: { LanguageSettings.shared.preference = $0 }
        )) {
          Text("简体中文").tag(AppLanguage.simplifiedChinese)
          Text("English").tag(AppLanguage.english)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("notice.language")
        Text(L10n.text("notice.title")).font(.largeTitle.bold())
        Text(L10n.text("notice.version", FirstUseNoticeStore.currentVersion))
          .font(.caption).foregroundStyle(.secondary)
        Text(L10n.text("notice.summary"))
        ForEach(["records", "health", "reports", "control", "backup", "use"], id: \.self) { section in
          VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("notice.\(section).title")).font(.headline)
            Text(L10n.text("notice.\(section).body"))
          }
        }
        if !readOnly {
          if declined { Text(L10n.text("notice.restricted")).accessibilityIdentifier("notice.restricted") }
          if notice.storageFailed { Text(L10n.text("notice.saveError")).foregroundStyle(.secondary) }
          if let message { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("notice.status") }
          Button(L10n.text("settings.export"), action: export)
            .accessibilityIdentifier("notice.export")
          Button(L10n.text("settings.disconnectConfirm"), role: .destructive) { showDeleteHealth = true }
            .disabled(healthAccess.isBusy)
            .accessibilityIdentifier("notice.deleteHealth")
          Button(L10n.text("notice.deleteAll"), role: .destructive) { showDeleteAll = true }
            .disabled(healthAccess.isBusy)
            .accessibilityIdentifier("notice.deleteAll")
        }
      }
      .frame(maxWidth: 680, alignment: .leading)
      .padding()
      .frame(maxWidth: .infinity)
    }
    .accessibilityIdentifier("notice.page")
    .safeAreaInset(edge: .bottom) {
      if !readOnly {
        VStack(spacing: 10) {
          Button(L10n.text("notice.agree")) {
            do { try notice.accept() }
            catch { message = L10n.text("notice.saveError") }
          }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("notice.agree")
          Button(L10n.text("notice.notNow")) { declined = true }
            .accessibilityIdentifier("notice.notNow")
        }
        .frame(maxWidth: .infinity).padding().background(.regularMaterial)
      }
    }
    .fileExporter(isPresented: $showExporter, document: exportDocument,
                  contentType: .json, defaultFilename: "trainote-backup.json") { result in
      if case .failure = result { message = L10n.text("notice.saveError") }
    }
    .confirmationDialog(L10n.text("settings.disconnectQuestion"), isPresented: $showDeleteHealth, titleVisibility: .visible) {
      Button(L10n.text("settings.disconnectConfirm"), role: .destructive) {
        Task { await healthAccess.disconnectHealth() }
      }
      Button(L10n.text("settings.cancel"), role: .cancel) {}
    } message: { Text(L10n.text("settings.disconnectHelp")) }
    .confirmationDialog(L10n.text("notice.deleteAll"), isPresented: $showDeleteAll, titleVisibility: .visible) {
      Button(L10n.text("notice.deleteAll"), role: .destructive) { deleteAll() }
      Button(L10n.text("settings.cancel"), role: .cancel) {}
    } message: { Text(L10n.text("notice.deleteAllHelp")) }
    .healthAccessError(healthAccess)
  }

  private func export() {
    do {
      exportDocument = BackupDocument(data: try BackupArchiveService.export(context: modelContext))
      showExporter = true
    } catch { message = L10n.text("notice.saveError") }
  }

  private func deleteAll() {
    Task {
      do {
        try FirstUseNoticeDataDeletion.deleteManualRecords(context: modelContext)
        try healthAccess.reports.deleteAllReports()
        await healthAccess.disconnectHealth()
        message = L10n.text(healthAccess.healthDeletionNeedsRetry ? "notice.deleteFailed" : "notice.deleted")
      } catch { message = L10n.text("notice.deleteFailed") }
    }
  }
}

@MainActor
enum FirstUseNoticeDataDeletion {
  static func deleteManualRecords(context: ModelContext) throws {
    // Delete in one explicit save transaction. The acknowledgment/preference files are independent.
    do {
      for type in PersistenceController.modelTypes { try delete(type, context: context) }
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }
  private static func delete<T: PersistentModel>(_ type: T.Type, context: ModelContext) throws {
    for record in try context.fetch(FetchDescriptor<T>()) { context.delete(record) }
  }
}
