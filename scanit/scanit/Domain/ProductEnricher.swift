import Foundation
import OSLog
import ScanItCore
import SwiftData

/// Fills product names and photos from Open Food Facts after an item is added (BACKLOG INS-101).
///
/// Never blocks a scan. Every code gets a `Product` row; `offFetchedAt == nil` means "still to
/// look up", which is the offline queue. `flush()` runs after each add, on launch and whenever
/// the network comes back.
@Observable
final class ProductEnricher {
    /// Unknown products are asked about again after this long; OFF grows every day.
    static let missRetryInterval: TimeInterval = 7 * 86_400

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let lookup: any ProductLookup
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private let logger = Logger(subsystem: "com.fernandocorreia.scanit", category: "off")

    init(context: ModelContext, lookup: any ProductLookup = OpenFoodFactsClient(), now: @escaping () -> Date = { .now }) {
        self.context = context
        self.lookup = lookup
        self.now = now
    }

    /// Cached info for a code, without touching the network. Used to name a product in the
    /// confirm sheet when it has been seen before.
    func cached(_ code: ScannedCode) -> Product? {
        guard Self.isLookupable(code) else { return nil }
        return product(for: code.value)
    }

    /// Call after an item is added: copies a cached name across at once, otherwise queues it.
    func enqueue(_ item: CartItem) {
        let code = item.scannedCode
        guard Self.isLookupable(code) else { return }
        let product = product(for: code.value) ?? {
            let new = Product(gtin: code.value)
            context.insert(new)
            return new
        }()
        apply(product, to: [item])
        try? context.save()
    }

    /// Looks up every queued product. Network errors leave them queued for the next flush.
    func flush() async {
        for product in pending() where !inFlight.contains(product.gtin) {
            inFlight.insert(product.gtin)
            defer { inFlight.remove(product.gtin) }
            let code = ScannedCode(kind: .gtin, value: product.gtin)
            do {
                switch try await lookup.lookup(code: code.displayValue) {
                case .found(let info):
                    product.name = info.name
                    product.brand = info.brand
                    product.imageURL = info.imageURL
                    product.categories = info.categories
                    product.offMiss = false
                case .notFound:
                    product.offMiss = true
                }
                product.offFetchedAt = now()
                apply(product, to: itemsMissingDetails(code: product.gtin))
                try? context.save()
            } catch {
                logger.info("lookup deferred for \(product.gtin, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return // offline or OFF down: stop, the rest stays queued
            }
        }
    }

    // MARK: - Internals

    /// In-store codes (weighed produce, deli) mean different things in different shops, and
    /// opaque codes are not products, so neither is looked up.
    static func isLookupable(_ code: ScannedCode) -> Bool {
        code.kind == .gtin && !code.isInStore
    }

    private func product(for gtin: String) -> Product? {
        var descriptor = FetchDescriptor<Product>(predicate: #Predicate { $0.gtin == gtin })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func pending() -> [Product] {
        let retryBefore = now().addingTimeInterval(-Self.missRetryInterval)
        let descriptor = FetchDescriptor<Product>(
            predicate: #Predicate { $0.offFetchedAt == nil || ($0.offMiss && ($0.offFetchedAt ?? retryBefore) < retryBefore) }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func itemsMissingDetails(code: String) -> [CartItem] {
        let descriptor = FetchDescriptor<CartItem>(
            predicate: #Predicate { $0.code == code && ($0.productName == nil || $0.imageURL == nil) }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Only fills blanks: a name the user typed or edited is never overwritten.
    private func apply(_ product: Product, to items: [CartItem]) {
        for item in items {
            if item.productName == nil, let name = product.displayName { item.productName = name }
            if item.imageURL == nil { item.imageURL = product.imageURL }
        }
    }
}

nonisolated extension Product {
    /// "Nutella" or "Leite meio gordo · Mimosa"; brand alone when OFF has no name.
    var displayName: String? {
        switch (name, brand) {
        case let (name?, brand?) where !name.localizedCaseInsensitiveContains(brand): "\(name) · \(brand)"
        case let (name?, _): name
        case let (nil, brand?): brand
        case (nil, nil): nil
        }
    }
}
