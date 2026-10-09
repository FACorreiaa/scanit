import Foundation
import ScanItCore

extension Money {
    /// Locale-formatted for display, in the money's own currency ("€1.99", "1,99 €", "¥198").
    func formatted(locale: Locale = .autoupdatingCurrent) -> String {
        decimalValue.formatted(
            .currency(code: currency)
                .locale(locale)
                .precision(.fractionLength(minorUnitDigits))
        )
    }
}
