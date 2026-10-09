import Foundation
import ScanItCore
import SwiftData

/// INS-06 for one product in one store: the badge on cart rows ("↑ 12% since May", BACKLOG INS-104).
struct PriceTrend: Equatable {
    let percent: Double
    let since: Date

    /// Rounded to whole percent; smaller moves are noise on a shelf label.
    var roundedPercent: Int { Int(percent.rounded()) }

    static let windowDays = 180

    static func lookup(code: String, store: Store?, context: ModelContext, now: Date = .now) -> PriceTrend? {
        guard let store else { return nil }
        let storeID = store.id
        let since = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let descriptor = FetchDescriptor<PriceObservation>(
            predicate: #Predicate { $0.code == code && $0.deletedAt == nil && $0.observedAt >= since },
            sortBy: [SortDescriptor(\.observedAt)]
        )
        let rows = ((try? context.fetch(descriptor)) ?? []).filter { $0.store?.id == storeID }
        guard let first = rows.first, let latest = rows.last, first.priceMinor > 0,
              first.currency == latest.currency else { return nil }
        let trend = PriceTrend(
            percent: Double(latest.priceMinor - first.priceMinor) / Double(first.priceMinor) * 100,
            since: first.observedAt
        )
        return trend.roundedPercent == 0 ? nil : trend
    }
}
