import Algorithms
import Foundation
import ScanItCore
import SwiftData

/// What the start-trip sheet offers (`DESIGN.md` §2): recent stores with the last one used
/// preselected, and limit chips taken from the user's own history.
struct TripStartOptions {
    struct LimitSuggestion: Hashable, Identifiable {
        enum Kind: Hashable { case estimate, lastLimit, averageTrip }
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

    /// - Parameter including: a store that must be offered even if it is not among the recent ones
    ///   (MEAL-004: the list's cheapest store). It goes first when it would otherwise be left out.
    init(context: ModelContext, now: Date = .now, including storeID: UUID? = nil) {
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
        let ordered = Array((sessions.compactMap(\.store) + stores)
            .filter { !$0.isSoftDeleted }
            .uniqued(on: \.id))
        var recent = Array(ordered.prefix(Self.maxRecentStores))
        if let storeID, !recent.contains(where: { $0.id == storeID }),
           let store = ordered.first(where: { $0.id == storeID }) {
            recent.insert(store, at: 0)
        }

        self.sessions = sessions
        self.now = now
        self.recentStores = recent
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
            let roundedUp = Self.roundedUp(Money(amountMinor: average, currency: currency))
            if roundedUp.amountMinor > 0, roundedUp != suggestions.first?.amount {
                suggestions.append(LimitSuggestion(kind: .averageTrip, amount: roundedUp))
            }
        }
        return suggestions
    }

    /// The chips with the list's estimate first (MEAL-004), when it is in this currency. A chip
    /// with the same amount as the estimate is dropped.
    func limitSuggestions(currency: String, estimate: Money?) -> [LimitSuggestion] {
        let history = limitSuggestions(currency: currency)
        guard let estimate, estimate.currency.uppercased() == currency.uppercased() else { return history }
        return [LimitSuggestion(kind: .estimate, amount: estimate)] + history.filter { $0.amount != estimate }
    }

    /// Up to the next whole unit (€41,20 → €42), so a limit reads as a round number.
    static func roundedUp(_ money: Money) -> Money {
        let unit = (0..<Money.minorUnitDigits(for: money.currency)).reduce(1) { value, _ in value * 10 }
        return Money(amountMinor: (money.amountMinor + unit - 1) / unit * unit, currency: money.currency)
    }
}
