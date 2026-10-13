import Foundation

/// An editing session captures its locale. Never reinterpret a draft when interface language changes.
enum DecimalInput {
  static func parse(_ text: String, locale: Locale) -> Double? {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let separator = locale.decimalSeparator ?? "."
    let escaped = NSRegularExpression.escapedPattern(for: separator)
    guard value.range(of: "^[+-]?[0-9]+(?:\(escaped)[0-9]*)?$", options: .regularExpression) != nil,
      let number = Double(value.replacingOccurrences(of: separator, with: ".")), number.isFinite
    else { return nil }
    return number
  }
}
