import Foundation
import ScanItCore
import SwiftData

// SwiftData models (`ARCHITECTURE.md` → Data model). Shaped for sync from day one: every synced
// row has a client UUID, `updatedAt`, a soft-delete `deletedAt` and a `syncState`, so P4 adds a
// sync engine without migrating shapes. Enums are stored as raw strings so `#Predicate` can
// filter on them. Money is integer minor units plus an ISO currency code.

nonisolated enum SyncState: String, Codable {
    case dirty, synced
}

/// Common bookkeeping for rows that sync.
nonisolated protocol SyncedRecord: AnyObject {
    var id: UUID { get }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    var syncStateRaw: String { get set }
}

nonisolated extension SyncedRecord {
    var isSoftDeleted: Bool { deletedAt != nil }

    /// Call after every user-visible change.
    func touch(_ now: Date = .now) {
        updatedAt = now
        syncStateRaw = SyncState.dirty.rawValue
    }

    func softDelete(_ now: Date = .now) {
        deletedAt = now
        touch(now)
    }
}

@Model
nonisolated final class Store: SyncedRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var chain: String?
    var countryCode: String
    var currency: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStateRaw: String

    @Relationship(deleteRule: .nullify, inverse: \ShoppingSession.store)
    var sessions: [ShoppingSession] = []

    init(name: String, chain: String? = nil, countryCode: String, currency: String, now: Date = .now) {
        self.id = UUID()
        self.name = name
        self.chain = chain
        self.countryCode = countryCode
        self.currency = currency.uppercased()
        self.createdAt = now
        self.updatedAt = now
        self.syncStateRaw = SyncState.dirty.rawValue
    }
}

@Model
nonisolated final class ShoppingSession: SyncedRecord {
    @Attribute(.unique) var id: UUID
    var store: Store?
    var limitMinor: Int?
    var currency: String
    var startedAt: Date
    var endedAt: Date?
    var statusRaw: String
    var tillTotalMinor: Int?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStateRaw: String

    @Relationship(deleteRule: .cascade, inverse: \CartItem.session)
    var items: [CartItem] = []

    init(store: Store?, limitMinor: Int?, currency: String, now: Date = .now) {
        self.id = UUID()
        self.store = store
        self.limitMinor = limitMinor
        self.currency = currency.uppercased()
        self.startedAt = now
        self.statusRaw = SessionStatus.active.rawValue
        self.createdAt = now
        self.updatedAt = now
        self.syncStateRaw = SyncState.dirty.rawValue
    }

    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var liveItems: [CartItem] {
        items.filter { !$0.isSoftDeleted }
    }

    /// Σ quantity × unit price over items that are not deleted.
    var totalMinor: Int {
        liveItems.reduce(0) { $0 + $1.lineTotalMinor }
    }

    var total: Money { Money(amountMinor: totalMinor, currency: currency) }
    /// Σ quantity over items that are not deleted: "2 × milk" is two items.
    var itemCount: Int { liveItems.reduce(0) { $0 + $1.quantity } }
    var limit: Money? { limitMinor.map { Money(amountMinor: $0, currency: currency) } }
    var limitStatus: LimitStatus { LimitStatus(totalMinor: totalMinor, limitMinor: limitMinor) }
}

@Model
nonisolated final class CartItem: SyncedRecord {
    @Attribute(.unique) var id: UUID
    var session: ShoppingSession?
    var code: String
    var codeKindRaw: String
    var productName: String?
    /// Open Food Facts thumbnail; display only, not synced (each device refills it).
    var imageURL: URL?
    var quantity: Int
    var weightGrams: Int?
    var unitPriceMinor: Int
    var priceSourceRaw: String
    var scannedAt: Date
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStateRaw: String

    init(
        code: ScannedCode, productName: String? = nil, quantity: Int = 1,
        unitPriceMinor: Int, priceSource: PriceSource, now: Date = .now
    ) {
        self.id = UUID()
        self.code = code.value
        self.codeKindRaw = code.kind.rawValue
        self.productName = productName
        self.quantity = quantity
        self.unitPriceMinor = unitPriceMinor
        self.priceSourceRaw = priceSource.rawValue
        self.scannedAt = now
        self.createdAt = now
        self.updatedAt = now
        self.syncStateRaw = SyncState.dirty.rawValue
    }

    var scannedCode: ScannedCode {
        ScannedCode(kind: ScannedCode.Kind(rawValue: codeKindRaw) ?? .opaque, value: code)
    }

    var priceSource: PriceSource {
        get { PriceSource(rawValue: priceSourceRaw) ?? .manual }
        set { priceSourceRaw = newValue.rawValue }
    }

    var lineTotalMinor: Int { unitPriceMinor * quantity }
}

/// Open Food Facts cache. Not user data, never synced; each device refetches.
@Model
nonisolated final class Product {
    @Attribute(.unique) var gtin: String
    var name: String?
    var brand: String?
    var imageURL: URL?
    var categories: [String]
    /// `nil` = lookup still pending (offline queue, `ARCHITECTURE.md` → Offline).
    var offFetchedAt: Date?
    /// True when OFF answered "unknown product"; retried after a TTL.
    var offMiss: Bool

    init(gtin: String) {
        self.gtin = gtin
        self.categories = []
        self.offMiss = false
    }
}

/// Every confirmed price, kept forever: drives price memory and price-history insights.
@Model
nonisolated final class PriceObservation: SyncedRecord {
    @Attribute(.unique) var id: UUID
    var store: Store?
    var code: String
    var priceMinor: Int
    var currency: String
    var observedAt: Date
    var sourceRaw: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStateRaw: String

    init(store: Store, code: String, price: Money, source: PriceSource, now: Date = .now) {
        self.id = UUID()
        self.store = store
        self.code = code
        self.priceMinor = price.amountMinor
        self.currency = price.currency
        self.observedAt = now
        self.sourceRaw = source.rawValue
        self.createdAt = now
        self.updatedAt = now
        self.syncStateRaw = SyncState.dirty.rawValue
    }
}

enum ScanItSchema {
    static let models: [any PersistentModel.Type] = [
        Store.self, ShoppingSession.self, CartItem.self, Product.self, PriceObservation.self, ListItem.self,
        Meal.self, MealIngredient.self,
    ]

    static func container(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// A store in a file of its own, for tests that close and reopen it ("survives a relaunch").
    static func container(url: URL) throws -> ModelContainer {
        let schema = Schema(models)
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
    }
}
