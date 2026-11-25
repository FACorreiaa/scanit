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

/// What the start sheet needs to open at the list's cheapest store with the estimate as its limit,
/// and the plan the trip keeps (MEAL-005).
struct TripPrefill: Equatable {
    /// The store to preselect.
    let storeID: UUID
    /// The list's estimate at each store that has one, so the limit follows the chosen store.
    let estimates: [UUID: Money]
    /// Lines each of those stores had a price for.
    let pricedLines: [UUID: Int]
    /// Every line the estimate was made from.
    let lineCount: Int
    /// The lines still to get, frozen for the trip.
    let lines: [PlannedLine]

    /// `lines` is the list as shown; ticked lines are left out, as the estimate leaves them out.
    init?(_ estimate: ListCostEstimate, lines: [ListItem] = []) {
        guard let cheapest = estimate.cheapest, let id = UUID(uuidString: cheapest.storeId) else { return nil }
        storeID = id
        var estimates: [UUID: Money] = [:]
        var pricedLines: [UUID: Int] = [:]
        for store in estimate.stores {
            guard let id = UUID(uuidString: store.storeId) else { continue }
            estimates[id] = store.total
            pricedLines[id] = store.pricedLines
        }
        self.estimates = estimates
        self.pricedLines = pricedLines
        lineCount = estimate.lines
        self.lines = lines.filter { !$0.isDone }.map { PlannedLine(text: $0.text, code: $0.code) }
    }

    /// The limit for a store: its estimate rounded up to a whole unit, as the other limit chips are.
    func limit(for storeID: UUID?) -> Money? {
        guard let storeID, let estimate = estimates[storeID], estimate.amountMinor > 0 else { return nil }
        return TripStartOptions.roundedUp(estimate)
    }

    /// The plan for the store the trip actually starts at: its plain estimate (not the rounded,
    /// editable limit). A new store, a store with no prices, or another currency has no planned
    /// cost, but the lines still count.
    func plan(for storeID: UUID?, currency: String) -> TripPlan {
        let estimate = storeID.flatMap { estimates[$0] }
        guard let storeID, let estimate, estimate.currency == currency.uppercased(), estimate.amountMinor > 0 else {
            return TripPlan(lines: lines, cost: nil, unpricedLines: lineCount)
        }
        return TripPlan(lines: lines, cost: estimate, unpricedLines: lineCount - (pricedLines[storeID] ?? 0))
    }
}

/// A list line as it was when the trip started.
struct PlannedLine: Equatable {
    let text: String
    let code: String?
}

/// What a trip started from the list keeps (MEAL-005).
struct TripPlan: Equatable {
    let lines: [PlannedLine]
    /// The list's estimate at the trip's store, `nil` when there was none.
    let cost: Money?
    /// Lines the cost leaves out, for want of a price at that store.
    let unpricedLines: Int
}
