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

/// The lowest price currently known for a product in another store.
struct PriceElsewhere: Equatable {
    let storeName: String
    let price: Money
    let observedAt: Date

    func isCheaper(than other: Money?) -> Bool {
        guard let other, other.currency == price.currency else { return false }
        return price.amountMinor < other.amountMinor
    }
}

extension PriceMemory {
    /// Older sightings say little about what the other shop charges today.
    static let elsewhereMaxAge: TimeInterval = 90 * 86_400

    /// The cheapest other store for a product, by each store's newest price. Only real GTINs:
    /// an in-store or opaque code means a different product in every shop.
    static func cheapestElsewhere(
        code: ScannedCode, store: Store?, currency: String, context: ModelContext, now: Date = .now
    ) -> PriceElsewhere? {
        guard code.kind == .gtin, !code.isInStore else { return nil }
        let value = code.value
        let since = now.addingTimeInterval(-elsewhereMaxAge)
        let descriptor = FetchDescriptor<PriceObservation>(
            predicate: #Predicate { $0.code == value && $0.deletedAt == nil && $0.observedAt >= since },
            sortBy: [SortDescriptor(\.observedAt, order: .reverse)]
        )
        var seen: Set<UUID> = []
        let newestPerStore = ((try? context.fetch(descriptor)) ?? []).filter { observation in
            guard let other = observation.store, other.deletedAt == nil else { return false }
            return seen.insert(other.id).inserted
        }
        let cheapest = newestPerStore
            .filter { $0.store?.id != store?.id && $0.currency == currency }
            .min { ($0.priceMinor, $1.observedAt) < ($1.priceMinor, $0.observedAt) }
        guard let cheapest, let name = cheapest.store?.name else { return nil }
        return PriceElsewhere(
            storeName: name,
            price: Money(amountMinor: cheapest.priceMinor, currency: cheapest.currency),
            observedAt: cheapest.observedAt
        )
    }
}
