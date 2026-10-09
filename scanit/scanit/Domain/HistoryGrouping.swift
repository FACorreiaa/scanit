import Foundation
import ScanItCore

/// Finished trips grouped by calendar month, newest first (`DESIGN.md` → History, BACKLOG IOS-011).
struct MonthGroup: Identifiable {
    let monthStart: Date
    let trips: [ShoppingSession]
    /// One total per currency; never converted (`ARCHITECTURE.md` → Principles).
    let totals: [Money]

    var id: Date { monthStart }

    static func group(_ sessions: [ShoppingSession], calendar: Calendar = .current) -> [MonthGroup] {
        let byMonth = Dictionary(grouping: sessions) { session in
            calendar.dateInterval(of: .month, for: session.startedAt)?.start ?? session.startedAt
        }
        return byMonth
            .map { start, trips in
                let sorted = trips.sorted { $0.startedAt > $1.startedAt }
                var perCurrency: [String: Int] = [:]
                for trip in sorted { perCurrency[trip.currency, default: 0] += trip.totalMinor }
                let totals = perCurrency
                    .sorted { $0.value > $1.value }
                    .map { Money(amountMinor: $0.value, currency: $0.key) }
                return MonthGroup(monthStart: start, trips: sorted, totals: totals)
            }
            .sorted { $0.monthStart > $1.monthStart }
    }
}
