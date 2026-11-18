import Foundation
import Testing
@testable import ScanItCore

/// `Fixtures/meal-cost.json`: hand-computed expectations, shared with Android.
private struct MealCostFixture: Decodable {
    struct Line: Decodable { let priceMinor: Int?; let storeId: String?; let lineTotalMinor: Int? }
    struct Expected: Decodable {
        let totalMinor: Int
        let perServingMinor: Int?
        let priced, unpriced: Int
        let lines: [Line]?
    }
    struct Case: Decodable { let name, currency: String; let servings: Int; let expected: Expected }

    let now: Date
    let prices: [PriceSnapshot]
    let ingredients: [IngredientSnapshot]
    let cases: [Case]
}

@Suite("Meal cost (MEAL-001)")
struct MealCostTests {
    private let fixture: MealCostFixture

    init() throws {
        fixture = try WireCoding.decoder().decode(MealCostFixture.self, from: Fixtures.data("meal-cost.json"))
    }

    @Test func fixtureCases() {
        for item in fixture.cases {
            let estimate = MealCost.estimate(
                ingredients: fixture.ingredients, servings: item.servings, prices: fixture.prices,
                currency: item.currency, now: fixture.now
            )
            let want = item.expected
            #expect(estimate.total == Money(amountMinor: want.totalMinor, currency: item.currency), "\(item.name)")
            #expect(estimate.perServing?.amountMinor == want.perServingMinor, "\(item.name)")
            #expect(estimate.perServing.map(\.currency) ?? item.currency == item.currency, "\(item.name)")
            #expect(estimate.pricedLines == want.priced, "\(item.name)")
            #expect(estimate.unpricedLines == want.unpriced, "\(item.name)")
            #expect(estimate.lines.count == fixture.ingredients.count, "one line per ingredient, in order")
            guard let lines = want.lines else { continue }
            for (index, (line, expected)) in zip(estimate.lines, lines).enumerated() {
                #expect(line.price?.priceMinor == expected.priceMinor, "\(item.name) line \(index)")
                #expect(line.price?.storeId == expected.storeId, "\(item.name) line \(index)")
                #expect(line.lineTotal?.amountMinor == expected.lineTotalMinor, "\(item.name) line \(index)")
            }
        }
    }

    @Test func emptyMealCostsNothing() {
        let estimate = MealCost.estimate(ingredients: [], servings: 2, prices: fixture.prices, currency: "EUR", now: fixture.now)
        #expect(estimate.total.amountMinor == 0)
        #expect(estimate.perServing == nil)
        #expect(estimate.isComplete == false, "nothing to price is not a complete price")
    }

    @Test func completeOnlyWhenEveryIngredientHasAPrice() {
        let priced = Array(fixture.ingredients.prefix(3))
        let estimate = MealCost.estimate(ingredients: priced, servings: 1, prices: fixture.prices, currency: "EUR", now: fixture.now)
        #expect(estimate.isComplete)
        #expect(estimate.total.amountMinor == 747)
        #expect(estimate.perServing?.amountMinor == 747)
    }

    @Test func samePriceTwoStoresPicksTheMostRecentlySeen() throws {
        let day = 86_400.0
        let older = PriceSnapshot(storeId: "A", storeName: "Older", code: "05601234567892", priceMinor: 99,
                                  currency: "EUR", observedAt: fixture.now.addingTimeInterval(-6 * day))
        let newer = PriceSnapshot(storeId: "Z", storeName: "Newer", code: "05601234567892", priceMinor: 99,
                                  currency: "EUR", observedAt: fixture.now.addingTimeInterval(-2 * day))
        for prices in [[older, newer], [newer, older]] {
            let estimate = MealCost.estimate(
                ingredients: [IngredientSnapshot(code: "05601234567892", quantity: 1)], servings: 1,
                prices: prices, currency: "EUR", now: fixture.now
            )
            #expect(estimate.lines.first?.price?.storeId == "Z", "not the alphabetically first store")
        }
    }
}
