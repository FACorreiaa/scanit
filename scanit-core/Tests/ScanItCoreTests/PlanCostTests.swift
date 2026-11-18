import Foundation
import Testing
@testable import ScanItCore

/// `Fixtures/plan-cost.json`: hand-computed expectations, shared with Android.
private struct PlanCostFixture: Decodable {
    struct Meal: Decodable {
        let mealTotalMinor: Int?
        let currency: String
        let isComplete: Bool
        let mealServings, servings: Int

        var planned: PlannedMeal {
            PlannedMeal(
                mealTotal: mealTotalMinor.map { Money(amountMinor: $0, currency: currency) },
                isComplete: isComplete, mealServings: mealServings, servings: servings
            )
        }
    }
    struct Expected: Decodable {
        let costs: [Int?]
        let totalMinor, meals, priced, complete: Int
        let isComplete: Bool
    }
    struct Case: Decodable { let name, currency: String; let meals: [Meal]; let expected: Expected }

    let cases: [Case]
}

@Suite("Plan cost (MEAL-002)")
struct PlanCostTests {
    @Test func fixtureCases() throws {
        let fixture = try WireCoding.decoder().decode(PlanCostFixture.self, from: Fixtures.data("plan-cost.json"))
        for item in fixture.cases {
            let planned = item.meals.map(\.planned)
            let want = item.expected
            // A meal's own cost ignores the week's currency; the week drops other currencies.
            let ownCosts = zip(planned, item.meals).map { meal, raw in
                raw.currency == item.currency ? meal.cost?.amountMinor : nil
            }
            #expect(ownCosts == want.costs, "\(item.name)")
            let summary = PlanCost.summary(planned, currency: item.currency)
            #expect(summary.total == Money(amountMinor: want.totalMinor, currency: item.currency), "\(item.name)")
            #expect(summary.meals == want.meals, "\(item.name)")
            #expect(summary.pricedMeals == want.priced, "\(item.name)")
            #expect(summary.completeMeals == want.complete, "\(item.name)")
            #expect(summary.isComplete == want.isComplete, "\(item.name)")
            #expect(summary.unpricedMeals == want.meals - want.priced, "\(item.name)")
        }
    }

    @Test func fromAnEstimate() {
        let lines = [
            IngredientPrice(code: "05601234567892", quantity: 2, price: PriceSnapshot(
                storeId: "L", storeName: "Lidl", code: "05601234567892", priceMinor: 99, currency: "EUR",
                observedAt: .now
            )),
            IngredientPrice(code: nil, quantity: 1, price: nil),
        ]
        let estimate = MealCostEstimate(lines: lines, total: Money(amountMinor: 198, currency: "EUR"),
                                        perServing: Money(amountMinor: 99, currency: "EUR"))
        let planned = PlannedMeal(estimate: estimate, mealServings: 2, servings: 4)
        #expect(planned.cost == Money(amountMinor: 396, currency: "EUR"))
        #expect(planned.isComplete == false, "a typed ingredient has no price")

        let empty = MealCostEstimate(lines: [lines[1]], total: Money(amountMinor: 0, currency: "EUR"), perServing: nil)
        #expect(PlannedMeal(estimate: empty, mealServings: 2, servings: 2).cost == nil, "nothing priced is not free")
    }
}
