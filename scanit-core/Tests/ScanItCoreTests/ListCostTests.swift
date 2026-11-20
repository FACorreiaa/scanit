import Foundation
import Testing
@testable import ScanItCore

/// `Fixtures/list-cost.json`: hand-computed expectations, shared with Android.
private struct ListCostFixture: Decodable {
    struct Store: Decodable { let storeId: String; let totalMinor, pricedLines, missingLines: Int }
    struct Expected: Decodable { let unpricedLines: Int; let stores: [Store] }

    let now: Date
    let lines: [IngredientSnapshot]
    let prices: [PriceSnapshot]
    let expected: [String: Expected]
}

@Suite("List cost per store (MEAL-004)")
struct ListCostTests {
    private let fixture: ListCostFixture

    init() throws {
        fixture = try WireCoding.decoder().decode(ListCostFixture.self, from: Fixtures.data("list-cost.json"))
    }

    @Test(arguments: ["EUR", "USD"])
    func fixtureCases(currency: String) throws {
        let want = try #require(fixture.expected[currency])
        let estimate = ListCost.estimate(lines: fixture.lines, prices: fixture.prices, currency: currency, now: fixture.now)
        #expect(estimate.lines == fixture.lines.count)
        #expect(estimate.unpricedLines == want.unpricedLines, "\(currency)")
        #expect(estimate.stores.map(\.storeId) == want.stores.map(\.storeId), "\(currency) order")
        for (store, expected) in zip(estimate.stores, want.stores) {
            #expect(store.total == Money(amountMinor: expected.totalMinor, currency: currency), "\(store.storeId)")
            #expect(store.pricedLines == expected.pricedLines, "\(store.storeId)")
            #expect(store.missingLines == expected.missingLines, "\(store.storeId)")
        }
        #expect(estimate.cheapest?.storeId == want.stores.first?.storeId)
    }

    /// A store missing a price can be the cheapest sum, but is never the store offered.
    @Test func partialStoreNeverWinsByMissingPrices() throws {
        let estimate = ListCost.estimate(lines: fixture.lines, prices: fixture.prices, currency: "EUR", now: fixture.now)
        let partial = try #require(estimate.stores.first { $0.storeId == "P" })
        let cheapest = try #require(estimate.cheapest)
        #expect(partial.total.amountMinor < cheapest.total.amountMinor)
        #expect(cheapest.storeId == "L")
    }

    @Test func emptyListAndNoPrices() {
        let empty = ListCost.estimate(lines: [], prices: fixture.prices, currency: "EUR", now: fixture.now)
        #expect(empty.stores.isEmpty && empty.cheapest == nil && empty.unpricedLines == 0)

        let typed = ListCost.estimate(
            lines: [IngredientSnapshot(code: nil, quantity: 2)], prices: fixture.prices, currency: "EUR", now: fixture.now
        )
        #expect(typed.stores.isEmpty)
        #expect(typed.unpricedLines == 1)
    }
}
