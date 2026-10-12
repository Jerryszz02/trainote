import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
  case system
  case simplifiedChinese = "zh-Hans"
  case english = "en"

  var id: String { rawValue }
  var title: String {
    switch self {
    case .system: L10n.text("language.system")
    case .simplifiedChinese: "简体中文"
    case .english: "English"
    }
  }

  static func resolve(_ preference: AppLanguage, preferredLanguages: [String]) -> AppLanguage {
    guard preference == .system else { return preference }
    for identifier in preferredLanguages {
      let parts = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
      if parts.first == "en" { return .english }
      if parts.first == "zh", !parts.contains("hant"), !parts.contains("tw"), !parts.contains("hk"), !parts.contains("mo") {
        return .simplifiedChinese
      }
    }
    return .english
  }
}

/// Presentation only. This preference never enters records, report fingerprints, or calculation caches.
@Observable
final class LanguageSettings {
  static let preferenceKey = "appearance.language"
  static let shared: LanguageSettings = {
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset-language") {
      UserDefaults.standard.removeObject(forKey: preferenceKey)
    }
    #endif
    return LanguageSettings()
  }()
  private let defaults: UserDefaults
  private(set) var preferredLanguages: [String]
  private(set) var regionalLocale: Locale
  var preference: AppLanguage {
    didSet { defaults.set(preference.rawValue, forKey: Self.preferenceKey) }
  }

  init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages,
       regionalLocale: Locale = .current) {
    self.defaults = defaults
    self.preferredLanguages = preferredLanguages
    self.regionalLocale = regionalLocale
    preference = AppLanguage(rawValue: defaults.string(forKey: Self.preferenceKey) ?? "") ?? .system
  }

  var language: AppLanguage { AppLanguage.resolve(preference, preferredLanguages: preferredLanguages) }
  var locale: Locale {
    var components = Locale.Components(identifier: regionalLocale.identifier)
    let selectedLanguage = Locale.Language.Components(identifier: language.rawValue)
    components.languageComponents.languageCode = selectedLanguage.languageCode
    components.languageComponents.script = selectedLanguage.script
    return Locale(components: components)
  }

  func refreshSystem(preferredLanguages: [String] = Locale.preferredLanguages, regionalLocale: Locale = .current) {
    self.preferredLanguages = preferredLanguages
    self.regionalLocale = regionalLocale
  }
}

enum L10n {
  static var language: AppLanguage { LanguageSettings.shared.language }
  static var locale: Locale { LanguageSettings.shared.locale }
  private static let bundles: [AppLanguage: Bundle] = Dictionary(uniqueKeysWithValues:
    [AppLanguage.english, .simplifiedChinese].compactMap { language in
      Bundle.main.path(forResource: language.rawValue, ofType: "lproj")
        .flatMap(Bundle.init(path:)).map { (language, $0) }
    })

  static func text(_ key: String, _ arguments: CVarArg...) -> String {
    render(key, arguments: arguments)
  }

  static func render(_ key: String, arguments: [CVarArg], language: AppLanguage? = nil) -> String {
    let selected = language ?? self.language
    let fallback = bundles[.english]?.localizedString(forKey: key, value: key, table: nil) ?? key
    let format = bundles[selected]?.localizedString(forKey: key, value: fallback, table: nil) ?? fallback
    // NSString's localized format resolves catalog plural rules as well as positional arguments.
    return arguments.isEmpty ? format : String(format: format, locale: locale, arguments: arguments)
  }

  static func name(zh: String, en: String) -> String {
    let preferred = language == .simplifiedChinese ? zh : en
    return preferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? (language == .simplifiedChinese ? en : zh) : preferred
  }

  /// Retain the message identity while an alert is open; resolve the current language at display time.
  struct Message {
    private let resolve: () -> String
    init(_ key: String, _ arguments: CVarArg...) {
      resolve = { L10n.render(key, arguments: arguments) }
    }
    init(resolving: @escaping () -> String) { resolve = resolving }
    var text: String { resolve() }
  }
}
