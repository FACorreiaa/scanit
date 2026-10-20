import Algorithms
import Foundation
import ScanItCore
import SwiftData

/// Numbers on the finish screen (`DESIGN.md` §6, BACKLOG IOS-010).
struct TripSummary {
    let total: Money
    let limit: Money?
    let status: LimitStatus
    /// Units, not lines: 2 × milk counts as 2.
    let itemCount: Int
    /// The three most expensive lines (quantity × unit price).
    let biggestLines: [CartItem]
    /// Total of the previous finished trip at the same store, if any.
    let previousTotalAtStore: Money?

    /// Positive when this trip cost more than the previous one at the same store.
    var deltaVsPrevious: Money? {
        guard let previousTotalAtStore, previousTotalAtStore.currency == total.currency else { return nil }
        return Money(amountMinor: total.amountMinor - previousTotalAtStore.amountMinor, currency: total.currency)
    }

    init(session: ShoppingSession, context: ModelContext) {
        let items = session.liveItems
        total = session.total
        limit = session.limit
        status = session.limitStatus
        itemCount = items.reduce(0) { $0 + $1.quantity }
        biggestLines = items.min(count: 3, sortedBy: { $0.lineTotalMinor > $1.lineTotalMinor })

        let finished = SessionStatus.finished.rawValue
        let startedAt = session.startedAt
        let descriptor = FetchDescriptor<ShoppingSession>(
            predicate: #Predicate { $0.statusRaw == finished && $0.deletedAt == nil && $0.startedAt < startedAt },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let storeID = session.store?.id
        previousTotalAtStore = storeID.flatMap { id in
            (try? context.fetch(descriptor))?.first { $0.store?.id == id }?.total
        }
    }
}
