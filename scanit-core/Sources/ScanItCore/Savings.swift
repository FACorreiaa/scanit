import Foundation

// Savings: INS-11…14 (`DESIGN.md` → Insights catalogue, BACKLOG SAVE-001). Pure functions over the
// same snapshots as the other insights, so the server (P9) and Android compute the same numbers.
// Fixture: `scanit-core/Fixtures/savings.json`. Amounts are per currency, never converted.

/// INS-11 and INS-13 for one cart line. Only real GTINs get one (in-store and opaque codes are
/// skipped), because only they name the same product in another shop.
public struct LineSaving: Hashable, Sendable {
    public let code: String
    public let name: String?
    public let quantity: Int
    public let paidMinor: Int
    /// Median of the latest price at each other store. `nil` when no other store has a price in the
    /// window: the line is "unpriced" and saves 0.
    public let referenceMinor: Int?
    /// The cheapest latest price at another store, only when it is below what was paid.
    public let cheaperElsewhere: PriceSnapshot?
    /// INS-11: (reference − paid) × quantity. Negative when the line cost more than elsewhere.
    public let saving: Money
    /// INS-13: (paid − cheapest elsewhere) × quantity, never below 0.
    public let missed: Money

    public var isPriced: Bool { referenceMinor != nil }
}

/// Missed saving (INS-13) summed per store, biggest first.
public struct StoreMissedSaving: Hashable, Sendable {
    public let storeId: String
    public let storeName: String?
    public let missed: Money
}

/// INS-12 for one trip, with its lines.
public struct TripSaving: Hashable, Sendable {
    public let tripId: String
    public let lines: [LineSaving]
    public let saving: Money
    public let missed: Money
    public let missedByStore: [StoreMissedSaving]

    public var unpricedLines: Int { lines.count { !$0.isPriced } }
}

/// INS-14 (and INS-13 summed) over a period.
public struct PeriodSaving: Hashable, Sendable {
    public let saving: Money
    public let missed: Money
    public let trips: Int
    public let missedByStore: [StoreMissedSaving]
}

extension InsightsCalculator {
    /// Prices older than this, counted back from the trip's end, are not a reference.
    public static let savingWindowDays = 90

    /// INS-11…13 for one finished trip, measured against prices seen in the 90 days up to the trip's
    /// end, so a past trip's saving never moves. `nil` when the trip is in another currency.
    public func tripSaving(_ trip: TripSnapshot) -> TripSaving? {
        guard trip.currency.uppercased() == currency else { return nil }
        let since = trip.endedAt.addingTimeInterval(-Double(Self.savingWindowDays) * 86_400)
        let elsewhere = Dictionary(grouping: prices.filter {
            $0.storeId != trip.storeId && $0.observedAt >= since && $0.observedAt <= trip.endedAt
        }, by: \.code)

        let lines = trip.lines.filter(\.isTrackableProduct).map { line in
            lineSaving(line, latest: Self.latestPerStore(elsewhere[line.code] ?? []))
        }
        return TripSaving(
            tripId: trip.id,
            lines: lines,
            saving: money(lines.reduce(0) { $0 + $1.saving.amountMinor }),
            missed: money(lines.reduce(0) { $0 + $1.missed.amountMinor }),
            missedByStore: missedByStore(lines)
        )
    }

    /// INS-14: trip savings summed over the trips that ended in `interval`.
    public func savings(in interval: DateInterval) -> PeriodSaving {
        let results = trips(in: interval).compactMap(tripSaving)
        return PeriodSaving(
            saving: money(results.reduce(0) { $0 + $1.saving.amountMinor }),
            missed: money(results.reduce(0) { $0 + $1.missed.amountMinor }),
            trips: results.count,
            missedByStore: missedByStore(results.flatMap(\.lines))
        )
    }

    // MARK: - Helpers

    private func lineSaving(_ line: LineSnapshot, latest: [PriceSnapshot]) -> LineSaving {
        let reference = Self.median(latest.map(\.priceMinor))
        let cheapest = latest.min { ($0.priceMinor, $0.storeId) < ($1.priceMinor, $1.storeId) }
        let cheaper = cheapest.flatMap { $0.priceMinor < line.unitPriceMinor ? $0 : nil }
        return LineSaving(
            code: line.code,
            name: line.name,
            quantity: line.quantity,
            paidMinor: line.unitPriceMinor,
            referenceMinor: reference,
            cheaperElsewhere: cheaper,
            saving: money(reference.map { ($0 - line.unitPriceMinor) * line.quantity } ?? 0),
            missed: money(cheaper.map { (line.unitPriceMinor - $0.priceMinor) * line.quantity } ?? 0)
        )
    }

    private func missedByStore(_ lines: [LineSaving]) -> [StoreMissedSaving] {
        var totals: [String: (name: String?, minor: Int)] = [:]
        for line in lines {
            guard let store = line.cheaperElsewhere else { continue }
            totals[store.storeId, default: (store.storeName, 0)].minor += line.missed.amountMinor
        }
        return totals
            .map { StoreMissedSaving(storeId: $0.key, storeName: $0.value.name, missed: money($0.value.minor)) }
            .sorted { ($0.missed.amountMinor, $1.storeId) > ($1.missed.amountMinor, $0.storeId) }
    }

    /// The middle price; with an even count, the mean of the two middle prices rounded half up.
    /// Prices are positive, so integer `(a + b + 1) / 2` is half up.
    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid] + 1) / 2 : sorted[mid]
    }
}
