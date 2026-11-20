import Foundation

// What the shopping list costs at each store you know (BACKLOG MEAL-004). The same price rule as a
// meal's cost (MEAL-001): each store's latest price over the last 90 days, in one currency, for real
// GTINs only. Pure, so Android and the server add it up the same way.
// Fixture: `scanit-core/Fixtures/list-cost.json`.

/// The list at one store.
public struct StoreListCost: Hashable, Sendable {
    public let storeId: String
    public let storeName: String?
    /// The plain sum of this store's latest price × packs, over the lines it has a price for.
    public let total: Money
    /// Lines this store has a price for.
    public let pricedLines: Int
    /// Lines some other store has a price for, but not this one: the total leaves them out.
    public let missingLines: Int
}

public struct ListCostEstimate: Hashable, Sendable {
    /// Stores with at least one price, best first: most lines priced, then the lowest total. A store
    /// never ranks first by missing prices.
    public let stores: [StoreListCost]
    /// Every line on the list.
    public let lines: Int
    /// Lines no store has a price for: typed lines, in-store codes and products not seen lately.
    public let unpricedLines: Int

    /// The store to start the trip at: among those with the most lines priced, the cheapest.
    public var cheapest: StoreListCost? { stores.first }
}

public enum ListCost {
    /// Prices each line at every store's latest price in the window, in `currency`, times its packs.
    /// Never converts currencies.
    public static func estimate(
        lines: [IngredientSnapshot], prices: [PriceSnapshot], currency: String, now: Date
    ) -> ListCostEstimate {
        let currency = currency.uppercased()
        let since = now.addingTimeInterval(-Double(MealCost.windowDays) * 86_400)
        let byCode = Dictionary(grouping: prices.filter {
            $0.currency.uppercased() == currency && $0.observedAt >= since && $0.observedAt <= now
        }, by: \.code)

        var totals: [String: (name: String?, minor: Int, priced: Int)] = [:]
        var pricedAnywhere = 0
        for line in lines {
            let latest = line.priceableCode.map { InsightsCalculator.latestPerStore(byCode[$0] ?? []) } ?? []
            guard !latest.isEmpty else { continue }
            pricedAnywhere += 1
            let packs = max(line.quantity, 0)
            for price in latest {
                var entry = totals[price.storeId, default: (price.storeName, 0, 0)]
                entry.minor += price.priceMinor * packs
                entry.priced += 1
                totals[price.storeId] = entry
            }
        }

        let stores = totals.map { id, entry in
            StoreListCost(
                storeId: id, storeName: entry.name, total: Money(amountMinor: entry.minor, currency: currency),
                pricedLines: entry.priced, missingLines: pricedAnywhere - entry.priced
            )
        }
        .sorted {
            ($1.pricedLines, $0.total.amountMinor, $0.storeId) < ($0.pricedLines, $1.total.amountMinor, $1.storeId)
        }
        return ListCostEstimate(stores: stores, lines: lines.count, unpricedLines: lines.count - pricedAnywhere)
    }
}
