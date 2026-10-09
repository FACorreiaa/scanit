import Foundation
import ScanItCore
import SwiftData

/// The last price seen for a product in a store (`ARCHITECTURE.md` → Price memory, BACKLOG IOS-009).
struct RememberedPrice: Equatable {
    let price: Money
    let observedAt: Date
}

enum PriceMemory {
    /// Newest observation for `(store, code)`. Other stores never prefill: the same product
    /// costs different amounts in different shops, and in-store codes mean different products.
    static func lookup(code: String, store: Store?, context: ModelContext) -> RememberedPrice? {
        guard let store else { return nil }
        let storeID = store.id
        let descriptor = FetchDescriptor<PriceObservation>(
            predicate: #Predicate { $0.code == code && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.observedAt, order: .reverse)]
        )
        guard let observation = (try? context.fetch(descriptor))?.first(where: { $0.store?.id == storeID }) else {
            return nil
        }
        return RememberedPrice(
            price: Money(amountMinor: observation.priceMinor, currency: observation.currency),
            observedAt: observation.observedAt
        )
    }
}
