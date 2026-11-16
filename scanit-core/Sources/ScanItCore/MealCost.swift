import Foundation

// What a meal costs at the prices the user has seen (BACKLOG MEAL-001). Pure, so Android and the
// server compute the same thing. Fixture: `scanit-core/Fixtures/meal-cost.json`.

/// One ingredient as the estimate needs it: the product's code when it was picked from past
/// purchases (typed ingredients have none), and how many packs the meal takes.
public struct IngredientSnapshot: Hashable, Codable, Sendable {
    public var code: String?
    public var quantity: Int

    public init(code: String?, quantity: Int) {
        self.code = code
        self.quantity = quantity
    }

    /// Only a pack's own GTIN names the same product in every shop. Weighed and deli codes are
    /// per store and per weight, so they are never priced here.
    var priceableCode: String? {
        guard let code, !ScannedCode(kind: .gtin, value: code).isInStore else { return nil }
        return code
    }
}

/// One ingredient's price: the cheapest latest price seen at any store, or none.
public struct IngredientPrice: Hashable, Sendable {
    public let code: String?
    public let quantity: Int
    /// Where and when the price was seen. `nil` when the ingredient is unpriced.
    public let price: PriceSnapshot?

    public var lineTotal: Money? {
        price.map { Money(amountMinor: $0.priceMinor * quantity, currency: $0.currency) }
    }
}

public struct MealCostEstimate: Hashable, Sendable {
    /// One per ingredient, in the meal's order.
    public let lines: [IngredientPrice]
    /// Priced ingredients only: with unpriced ones the meal costs at least this.
    public let total: Money
    /// `total / servings`, rounded half up. `nil` when nothing is priced or servings < 1.
    public let perServing: Money?

    public var pricedLines: Int { lines.count { $0.price != nil } }
    public var unpricedLines: Int { lines.count - pricedLines }
    /// Every ingredient has a price, so `total` is the whole meal, not a floor.
    public var isComplete: Bool { !lines.isEmpty && unpricedLines == 0 }
}

public enum MealCost {
    /// Prices older than this are too stale to plan with.
    public static let windowDays = 90

    /// Prices each ingredient at the cheapest of the latest price per store over the last
    /// `windowDays`, in `currency`, times its packs. Never converts currencies.
    public static func estimate(
        ingredients: [IngredientSnapshot], servings: Int, prices: [PriceSnapshot], currency: String, now: Date
    ) -> MealCostEstimate {
        let currency = currency.uppercased()
        let since = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let byCode = Dictionary(grouping: prices.filter {
            $0.currency.uppercased() == currency && $0.observedAt >= since && $0.observedAt <= now
        }, by: \.code)

        let lines = ingredients.map { ingredient in
            let cheapest = ingredient.priceableCode.flatMap { code in
                // Same price at two stores: the one seen most recently is the surer bet.
                InsightsCalculator.latestPerStore(byCode[code] ?? []).min {
                    ($0.priceMinor, -$0.observedAt.timeIntervalSinceReferenceDate, $0.storeId)
                        < ($1.priceMinor, -$1.observedAt.timeIntervalSinceReferenceDate, $1.storeId)
                }
            }
            return IngredientPrice(code: ingredient.code, quantity: max(ingredient.quantity, 0), price: cheapest)
        }
        let totalMinor = lines.reduce(0) { $0 + ($1.lineTotal?.amountMinor ?? 0) }
        let anyPriced = lines.contains { $0.price != nil }
        let perServing = anyPriced && servings >= 1
            ? Money(amountMinor: (totalMinor + servings / 2) / servings, currency: currency)
            : nil
        return MealCostEstimate(lines: lines, total: Money(amountMinor: totalMinor, currency: currency), perServing: perServing)
    }
}
