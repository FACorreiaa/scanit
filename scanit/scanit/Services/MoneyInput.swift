import Foundation
import ScanItCore

/// Typed amounts: "60", "60,50" and "60.50" all work whatever the phone's locale, because people
/// copy the shelf label, not their region settings.
nonisolated enum MoneyInput {
    static func parse(_ text: String, currency: String) -> Money? {
        let cleaned = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty,
              cleaned.filter({ $0 == "." }).count <= 1,
              cleaned.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        return Money(decimal: value, currency: currency)
    }

    /// Text to put back in a field for editing: "1.99" → "1,99" in a comma locale.
    static func editingText(_ money: Money, locale: Locale = .autoupdatingCurrent) -> String {
        money.decimalValue.formatted(
            .number.grouping(.never).precision(.fractionLength(money.minorUnitDigits)).locale(locale)
        )
    }
}
