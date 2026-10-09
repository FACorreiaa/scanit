import Foundation

/// An amount of money in integer minor units (cents) plus an ISO 4217 currency code.
///
/// Wire shape: `{ "amountMinor": 199, "currency": "EUR" }` (`docs/api.md`). Never `Double`;
/// `Decimal` only at the UI edge via `decimalValue`.
public struct Money: Hashable, Codable, Sendable {
    public let amountMinor: Int
    public let currency: String

    public init(amountMinor: Int, currency: String) {
        self.amountMinor = amountMinor
        self.currency = currency.uppercased()
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            amountMinor: try container.decode(Int.self, forKey: .amountMinor),
            currency: try container.decode(String.self, forKey: .currency)
        )
    }

    /// `nil` when the currencies differ: totals are kept per currency, never converted.
    public func adding(_ other: Money) -> Money? {
        guard other.currency == currency else { return nil }
        return Money(amountMinor: amountMinor + other.amountMinor, currency: currency)
    }

    public func multiplied(by quantity: Int) -> Money {
        Money(amountMinor: amountMinor * quantity, currency: currency)
    }

    public var minorUnitDigits: Int { Self.minorUnitDigits(for: currency) }

    public var decimalValue: Decimal {
        Decimal(amountMinor) / pow(10, minorUnitDigits)
    }

    /// ISO 4217 exponent. Two unless listed.
    public static func minorUnitDigits(for currency: String) -> Int {
        switch currency.uppercased() {
        case "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG",
             "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF":
            0
        case "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND":
            3
        default:
            2
        }
    }
}
