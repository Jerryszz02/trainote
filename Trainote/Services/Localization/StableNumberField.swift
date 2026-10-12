import SwiftUI

/// Keep SwiftUI's text editor and its parsing format stable across presentation-language updates.
/// The raw, unfinished text belongs to TextField; it is not reformatted in an onChange callback.
struct StableNumberField<Format: ParseableFormatStyle>: View where Format.FormatOutput == String {
  private let title: String
  @Binding private var value: Format.FormatInput
  @State private var editingFormat: Format
  @State private var editingLocale: Locale

  init(_ title: String, value: Binding<Format.FormatInput>, format: Format) {
    self.title = title
    _value = value
    _editingFormat = State(initialValue: format)
    _editingLocale = State(initialValue: L10n.locale)
  }

  var body: some View {
    TextField(title, value: $value, format: editingFormat)
      .environment(\.locale, editingLocale)
  }
}

extension View {
  @ViewBuilder func localizationTestControls() -> some View {
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("-ui-testing-localization-controls") {
      self.overlay(alignment: .topTrailing) {
        HStack {
          Button("EN") { LanguageSettings.shared.preference = .english }
            .accessibilityIdentifier("localization.switch.en")
            .accessibilityValue(LanguageSettings.shared.preference.rawValue)
          Button("中") { LanguageSettings.shared.preference = .simplifiedChinese }
            .accessibilityIdentifier("localization.switch.zh-Hans")
            .accessibilityValue(LanguageSettings.shared.preference.rawValue)
        }
        .buttonStyle(.bordered).padding(4).background(.regularMaterial)
      }
    } else { self }
    #else
    self
    #endif
  }
}
