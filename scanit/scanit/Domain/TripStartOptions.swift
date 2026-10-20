import Algorithms
import Foundation
import ScanItCore
import SwiftData

/// What the start-trip sheet offers (`DESIGN.md` §2): recent stores with the last one used
/// preselected, and limit chips taken from the user's own history.
struct TripStartOptions {
    struct LimitSuggestion: Hashable, Identifiable {
        enum Kind: Hashable { case lastLimit, averageTrip }
        let kind: Kind
        let amount: Money
        var id: Kind { kind }
    }

    static let maxRecentStores = 8
    /// INS-02 window.
    static let averageWindowDays = 90

    let recentStores: [Store]
    let lastUsedStore: Store?
    private let sessions: [ShoppingSession]
    private let now: Date

    init(context: ModelContext, now: Date = .now) {
        let sessionDescriptor = FetchDescriptor<ShoppingSession>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let storeDescriptor = FetchDescriptor<Store>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let sessions = (try? context.fetch(sessionDescriptor)) ?? []
        let stores = (try? context.fetch(storeDescriptor)) ?? []

        // Most recently visited first, then stores never visited, newest first.
        let ordered = (sessions.compactMap(\.store) + stores)
            .filter { !$0.isSoftDeleted }
            .uniqued(on: \.id)

        self.sessions = sessions
        self.now = now
        self.recentStores = Array(ordered.prefix(Self.maxRecentStores))
        self.lastUsedStore = sessions.lazy.compactMap(\.store).first { !$0.isSoftDeleted }
    }

    /// Chips for the limit field, in the given currency. Empty on first use.
    func limitSuggestions(currency: String) -> [LimitSuggestion] {
        let currency = currency.uppercased()
        let sameCurrency = sessions.filter { $0.currency == currency }
        var suggestions: [LimitSuggestion] = []

        if let last = sameCurrency.lazy.compactMap(\.limitMinor).first {
            suggestions.append(LimitSuggestion(kind: .lastLimit, amount: Money(amountMinor: last, currency: currency)))
        }

        let windowStart = Calendar.current.date(byAdding: .day, value: -Self.averageWindowDays, to: now) ?? now
        let finished = sameCurrency.filter { $0.status == .finished && ($0.endedAt ?? $0.startedAt) >= windowStart }
        if !finished.isEmpty {
            let average = finished.map(\.totalMinor).reduce(0, +) / finished.count
            let unit = (0..<Money.minorUnitDigits(for: currency)).reduce(1) { value, _ in value * 10 }
            let roundedUp = (average + unit - 1) / unit * unit
            if roundedUp > 0, roundedUp != suggestions.first?.amount.amountMinor {
                suggestions.append(LimitSuggestion(kind: .averageTrip, amount: Money(amountMinor: roundedUp, currency: currency)))
            }
        }
        return suggestions
    }
}
