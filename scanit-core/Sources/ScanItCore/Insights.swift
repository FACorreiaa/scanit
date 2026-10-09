import Foundation

// Insights catalogue (`DESIGN.md` → Insights catalogue). Pure functions over value snapshots so iOS,
// Android and the server (P9) compute the same numbers. Fixture: `scanit-core/Fixtures/insights.json`.
// Amounts are always per currency, never converted.

public struct LineSnapshot: Hashable, Codable, Sendable {
    public var code: String
    public var codeKind: ScannedCode.Kind
    public var name: String?
    public var quantity: Int
    public var unitPriceMinor: Int
    /// First Open Food Facts category tag, if known.
    public var category: String?

    public init(code: String, codeKind: ScannedCode.Kind, name: String?, quantity: Int, unitPriceMinor: Int, category: String?) {
        self.code = code
        self.codeKind = codeKind
        self.name = name
        self.quantity = quantity
        self.unitPriceMinor = unitPriceMinor
        self.category = category
    }

    public var lineTotalMinor: Int { quantity * unitPriceMinor }

    /// A stable product across shops: a real GTIN that is not an in-store code.
    var isTrackableProduct: Bool {
        codeKind == .gtin && !ScannedCode(kind: .gtin, value: code).isInStore
    }
}

/// A finished trip.
public struct TripSnapshot: Hashable, Codable, Sendable {
    public var id: String
    public var storeId: String?
    public var storeName: String?
    public var currency: String
    public var startedAt: Date
    public var endedAt: Date
    public var limitMinor: Int?
    public var tillTotalMinor: Int?
    public var lines: [LineSnapshot]

    public init(
        id: String, storeId: String?, storeName: String?, currency: String, startedAt: Date, endedAt: Date,
        limitMinor: Int?, tillTotalMinor: Int?, lines: [LineSnapshot]
    ) {
        self.id = id
        self.storeId = storeId
        self.storeName = storeName
        self.currency = currency
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.limitMinor = limitMinor
        self.tillTotalMinor = tillTotalMinor
        self.lines = lines
    }

    public var totalMinor: Int { lines.reduce(0) { $0 + $1.lineTotalMinor } }
}

public struct PriceSnapshot: Hashable, Codable, Sendable {
    public var storeId: String
    public var storeName: String?
    public var code: String
    public var priceMinor: Int
    public var currency: String
    public var observedAt: Date

    public init(storeId: String, storeName: String?, code: String, priceMinor: Int, currency: String, observedAt: Date) {
        self.storeId = storeId
        self.storeName = storeName
        self.code = code
        self.priceMinor = priceMinor
        self.currency = currency
        self.observedAt = observedAt
    }
}

// MARK: - Results

public struct PeriodSpend: Hashable, Sendable {
    public let current: Money
    public let previous: Money
    public var delta: Money { Money(amountMinor: current.amountMinor - previous.amountMinor, currency: current.currency) }
    /// `nil` when the previous period had no spend.
    public var deltaPercent: Double? {
        previous.amountMinor == 0 ? nil : Double(delta.amountMinor) / Double(previous.amountMinor) * 100
    }
}

public struct LimitAdherence: Hashable, Sendable {
    public let under: Int
    public let withLimit: Int
    public var rate: Double { withLimit == 0 ? 0 : Double(under) / Double(withLimit) }
}

public struct StoreSpend: Hashable, Sendable {
    public let storeId: String?
    public let storeName: String?
    public let total: Money
}

public struct ProductSpend: Hashable, Sendable {
    public let code: String
    public let name: String?
    public let total: Money
    public let quantity: Int
}

public struct PriceChange: Hashable, Sendable {
    public let storeId: String
    public let storeName: String?
    public let code: String
    public let first: PriceSnapshot
    public let latest: PriceSnapshot
    public var percent: Double { Double(latest.priceMinor - first.priceMinor) / Double(first.priceMinor) * 100 }
}

public struct CheapestStore: Hashable, Sendable {
    public let code: String
    public let name: String?
    public let cheapest: PriceSnapshot
    public let dearest: PriceSnapshot
    public var saving: Money { Money(amountMinor: dearest.priceMinor - cheapest.priceMinor, currency: cheapest.currency) }
}

public struct CategorySpend: Hashable, Sendable {
    public static let other = "other"
    public let category: String
    public let total: Money
}

// MARK: - Calculator

public struct InsightsCalculator: Sendable {
    public enum Period: Sendable { case week, month }

    /// Charts appear from this many finished trips (`DESIGN.md`).
    public static let minimumTrips = 3

    public let currency: String
    public let now: Date
    public let calendar: Calendar
    private let trips: [TripSnapshot]
    private let prices: [PriceSnapshot]

    public init(trips: [TripSnapshot], prices: [PriceSnapshot], currency: String, now: Date, calendar: Calendar = .current) {
        let currency = currency.uppercased()
        self.currency = currency
        self.now = now
        self.calendar = calendar
        self.trips = trips.filter { $0.currency.uppercased() == currency }
        self.prices = prices.filter { $0.currency.uppercased() == currency }
    }

    public var hasEnoughData: Bool { trips.count >= Self.minimumTrips }

    public func interval(_ period: Period, offset: Int = 0) -> DateInterval {
        let component: Calendar.Component = period == .week ? .weekOfYear : .month
        let current = calendar.dateInterval(of: component, for: now)!
        guard offset != 0, let start = calendar.date(byAdding: component, value: offset, to: current.start) else {
            return current
        }
        return calendar.dateInterval(of: component, for: start)!
    }

    /// INS-01: this period vs the previous one, by `endedAt`.
    public func spend(_ period: Period) -> PeriodSpend {
        PeriodSpend(current: total(in: interval(period)), previous: total(in: interval(period, offset: -1)))
    }

    /// INS-02: mean trip total over the window, rounded to the nearest minor unit.
    public func averageTrip(windowDays: Int = 90) -> Money? {
        let recent = trips(inLast: windowDays)
        guard !recent.isEmpty else { return nil }
        let sum = recent.reduce(0) { $0 + $1.totalMinor }
        return money((sum + recent.count / 2) / recent.count)
    }

    /// INS-03: finished trips with a limit that stayed at or under it.
    public func limitAdherence(windowDays: Int = 90) -> LimitAdherence {
        let limited = trips(inLast: windowDays).filter { $0.limitMinor != nil }
        return LimitAdherence(under: limited.filter { $0.totalMinor <= $0.limitMinor! }.count, withLimit: limited.count)
    }

    /// INS-04: spend per store, biggest first.
    public func spendByStore(in interval: DateInterval) -> [StoreSpend] {
        let grouped = Dictionary(grouping: trips(in: interval)) { $0.storeId }
        return grouped
            .map { id, trips in
                StoreSpend(storeId: id, storeName: trips.first?.storeName, total: money(trips.reduce(0) { $0 + $1.totalMinor }))
            }
            .sorted { ($0.total.amountMinor, $1.storeId ?? "") > ($1.total.amountMinor, $0.storeId ?? "") }
    }

    /// INS-05: products by spend, biggest first. Only real GTINs (not in-store or opaque codes).
    public func topProducts(in interval: DateInterval, limit: Int = 10) -> [ProductSpend] {
        var totals: [String: (name: String?, minor: Int, quantity: Int)] = [:]
        for line in trips(in: interval).flatMap(\.lines) where line.isTrackableProduct {
            var entry = totals[line.code] ?? (line.name, 0, 0)
            entry.minor += line.lineTotalMinor
            entry.quantity += line.quantity
            entry.name = entry.name ?? line.name
            totals[line.code] = entry
        }
        return totals
            .map { ProductSpend(code: $0.key, name: $0.value.name, total: money($0.value.minor), quantity: $0.value.quantity) }
            .sorted { ($0.total.amountMinor, $1.code) > ($1.total.amountMinor, $0.code) }
            .prefix(limit)
            .map { $0 }
    }

    /// INS-06: per product and store, latest observation vs the first in the window. Only real
    /// changes, biggest rise first.
    public func priceChanges(windowDays: Int = 180) -> [PriceChange] {
        let since = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let grouped = Dictionary(grouping: prices.filter { $0.observedAt >= since && $0.observedAt <= now }) {
            "\($0.storeId)|\($0.code)"
        }
        return grouped.values
            .compactMap { observations -> PriceChange? in
                let sorted = observations.sorted { $0.observedAt < $1.observedAt }
                guard let first = sorted.first, let latest = sorted.last, first.priceMinor > 0,
                      first.priceMinor != latest.priceMinor else { return nil }
                return PriceChange(storeId: first.storeId, storeName: first.storeName, code: first.code, first: first, latest: latest)
            }
            .sorted { ($0.percent, $1.code) > ($1.percent, $0.code) }
    }

    /// INS-07: for products bought at least `minimumPurchases` times, where the latest price is
    /// lowest. Needs prices from two or more stores. Biggest saving first.
    public func cheapestStores(minimumPurchases: Int = 3) -> [CheapestStore] {
        var purchases: [String: (count: Int, name: String?)] = [:]
        for line in trips.flatMap(\.lines) where line.isTrackableProduct {
            purchases[line.code, default: (0, line.name)].count += 1
        }
        let regulars = purchases.filter { $0.value.count >= minimumPurchases }
        return regulars
            .compactMap { code, info -> CheapestStore? in
                let latestPerStore = Dictionary(grouping: prices.filter { $0.code == code && $0.observedAt <= now }) { $0.storeId }
                    .compactMap { $0.value.max { $0.observedAt < $1.observedAt } }
                guard latestPerStore.count >= 2,
                      let cheapest = latestPerStore.min(by: { ($0.priceMinor, $0.storeId) < ($1.priceMinor, $1.storeId) }),
                      let dearest = latestPerStore.max(by: { $0.priceMinor < $1.priceMinor }),
                      dearest.priceMinor > cheapest.priceMinor
                else { return nil }
                return CheapestStore(code: code, name: info.name, cheapest: cheapest, dearest: dearest)
            }
            .sorted { ($0.saving.amountMinor, $1.code) > ($1.saving.amountMinor, $0.code) }
    }

    /// INS-08: spend by first Open Food Facts category; unknown is "other". Biggest first.
    public func categorySplit(in interval: DateInterval) -> [CategorySpend] {
        var totals: [String: Int] = [:]
        for line in trips(in: interval).flatMap(\.lines) {
            totals[line.category ?? CategorySpend.other, default: 0] += line.lineTotalMinor
        }
        return totals
            .map { CategorySpend(category: $0.key, total: money($0.value)) }
            .sorted { ($0.total.amountMinor, $1.category) > ($1.total.amountMinor, $0.category) }
    }

    // MARK: - Helpers

    private func trips(in interval: DateInterval) -> [TripSnapshot] {
        trips.filter { $0.endedAt >= interval.start && $0.endedAt < interval.end }
    }

    private func trips(inLast days: Int) -> [TripSnapshot] {
        let since = now.addingTimeInterval(-Double(days) * 86_400)
        return trips.filter { $0.endedAt >= since && $0.endedAt <= now }
    }

    private func total(in interval: DateInterval) -> Money {
        money(trips(in: interval).reduce(0) { $0 + $1.totalMinor })
    }

    private func money(_ minor: Int) -> Money {
        Money(amountMinor: minor, currency: currency)
    }
}
