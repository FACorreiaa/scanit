import Foundation
import Testing
@testable import ScanItCore

@Suite("LimitStatus")
struct LimitStatusTests {
    private func status(total: Int, limit: Int?) -> LimitStatus {
        LimitStatus(totalMinor: total, limitMinor: limit)
    }

    @Test func noLimit() {
        let s = status(total: 4280, limit: nil)
        #expect(s.state == .noLimit)
        #expect(s.remainingMinor == nil)
        #expect(s.progress == nil)
    }

    // BACKLOG IOS-002: 79.99 %, 80 %, 100 %, 100.01 %.
    @Test(arguments: [
        (7999, LimitState.ok),
        (8000, LimitState.near),
        (10000, LimitState.near),
        (10001, LimitState.over),
    ])
    func boundaries(total: Int, expected: LimitState) {
        #expect(status(total: total, limit: 10000).state == expected)
    }

    @Test func emptyTripIsOK() {
        #expect(status(total: 0, limit: 6000).state == .ok)
    }

    @Test func remainingAndProgress() {
        let s = status(total: 4280, limit: 6000)
        #expect(s.remainingMinor == 1720)
        #expect(abs((s.progress ?? 0) - 0.7133) < 0.001)

        let over = status(total: 6340, limit: 6000)
        #expect(over.remainingMinor == -340)
        #expect((over.progress ?? 0) > 1)
    }

    @Test func nonPositiveLimitMeansNoLimit() {
        #expect(status(total: 100, limit: 0).state == .noLimit)
    }

    @Test func feedbackOnlyWhenCrossingUpwards() {
        #expect(LimitState.feedback(from: .ok, to: .near) == .warning)
        #expect(LimitState.feedback(from: .ok, to: .over) == .error)
        #expect(LimitState.feedback(from: .near, to: .over) == .error)
        #expect(LimitState.feedback(from: .near, to: .near) == nil)
        #expect(LimitState.feedback(from: .over, to: .near) == nil)
        #expect(LimitState.feedback(from: .near, to: .ok) == nil)
        #expect(LimitState.feedback(from: .noLimit, to: .noLimit) == nil)
    }

    @Test func itemsLeftEstimate() {
        // "€6.10 left · about 2 items" (DESIGN.md §5): remaining ÷ average item price, rounded down.
        #expect(status(total: 5390, limit: 6000).itemsLeft(averageItemMinor: 250) == 2)
        #expect(status(total: 6100, limit: 6000).itemsLeft(averageItemMinor: 250) == 0)
        #expect(status(total: 100, limit: nil).itemsLeft(averageItemMinor: 250) == nil)
        #expect(status(total: 100, limit: 6000).itemsLeft(averageItemMinor: 0) == nil)
    }
}

@Suite("Money from decimal")
struct MoneyDecimalTests {
    @Test func roundsToMinorUnits() {
        #expect(Money(decimal: Decimal(string: "60")!, currency: "EUR") == Money(amountMinor: 6000, currency: "EUR"))
        #expect(Money(decimal: Decimal(string: "1.995")!, currency: "EUR") == Money(amountMinor: 200, currency: "EUR"))
        #expect(Money(decimal: Decimal(string: "198")!, currency: "JPY") == Money(amountMinor: 198, currency: "JPY"))
    }
}
