import Foundation
import Testing
@testable import ScanItCore

@Suite("Money")
struct MoneyTests {
    @Test func minorUnitDigits() {
        #expect(Money.minorUnitDigits(for: "EUR") == 2)
        #expect(Money.minorUnitDigits(for: "eur") == 2)
        #expect(Money.minorUnitDigits(for: "JPY") == 0)
        #expect(Money.minorUnitDigits(for: "KWD") == 3)
    }

    @Test func currencyIsUppercased() {
        #expect(Money(amountMinor: 1, currency: "eur").currency == "EUR")
    }

    @Test func sumRequiresSameCurrency() {
        let a = Money(amountMinor: 199, currency: "EUR")
        let b = Money(amountMinor: 1, currency: "EUR")
        #expect(a.adding(b) == Money(amountMinor: 200, currency: "EUR"))
        #expect(a.adding(Money(amountMinor: 1, currency: "USD")) == nil)
        #expect(a.multiplied(by: 3) == Money(amountMinor: 597, currency: "EUR"))
    }

    @Test func decimalValue() {
        #expect(Money(amountMinor: 199, currency: "EUR").decimalValue == Decimal(string: "1.99"))
        #expect(Money(amountMinor: 198, currency: "JPY").decimalValue == Decimal(198))
    }

    @Test func wireShape() throws {
        let json = try JSONEncoder().encode(Money(amountMinor: 199, currency: "EUR"))
        let object = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        #expect(object?["amountMinor"] as? Int == 199)
        #expect(object?["currency"] as? String == "EUR")
    }
}
