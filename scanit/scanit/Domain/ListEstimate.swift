import Foundation
import ScanItCore
import SwiftData

/// The shopping list's cost at each store you know (BACKLOG MEAL-004), from the lines still to get
/// and your own remembered prices. The maths is `ListCost` in ScanItCore.
enum ListEstimate {
    static func estimate(context: ModelContext, now: Date = .now) -> ListCostEstimate {
        let lines = ShoppingList.lines(context: context)
            .filter { !$0.isDone }
            .map { IngredientSnapshot(code: $0.code, quantity: $0.quantity) }
        let observations = (try? context.fetch(FetchDescriptor<PriceObservation>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))) ?? []
        // A store that was removed is never offered.
        let prices = observations.compactMap { observation -> PriceSnapshot? in
            guard let store = observation.store, !store.isSoftDeleted else { return nil }
            return PriceSnapshot(
                storeId: store.id.uuidString, storeName: store.name, code: observation.code,
                priceMinor: observation.priceMinor, currency: observation.currency, observedAt: observation.observedAt
            )
        }
        return ListCost.estimate(
            lines: lines, prices: prices, currency: InsightsSource.homeCurrency(context: context), now: now
        )
    }
}

/// What the start sheet needs to open at the list's cheapest store with the estimate as its limit.
struct TripPrefill: Equatable {
    /// The store to preselect.
    let storeID: UUID
    /// The list's estimate at each store that has one, so the limit follows the chosen store.
    let estimates: [UUID: Money]

    init?(_ estimate: ListCostEstimate) {
        guard let cheapest = estimate.cheapest, let id = UUID(uuidString: cheapest.storeId) else { return nil }
        storeID = id
        estimates = Dictionary(uniqueKeysWithValues: estimate.stores.compactMap { store in
            UUID(uuidString: store.storeId).map { ($0, store.total) }
        })
    }

    /// The limit for a store: its estimate rounded up to a whole unit, as the other limit chips are.
    func limit(for storeID: UUID?) -> Money? {
        guard let storeID, let estimate = estimates[storeID], estimate.amountMinor > 0 else { return nil }
        return TripStartOptions.roundedUp(estimate)
    }
}
