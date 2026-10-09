import Foundation
import Observation
import OSLog
import ScanItCore
import SwiftData

/// The active trip and its running total against the limit (`ARCHITECTURE.md` → Live total and limit).
///
/// Views read `active`, `limitState` and `feedback`; every mutation goes through here so the
/// limit state and the one-haptic-per-crossing rule stay in one place.
@Observable
final class SessionStore {
    /// A haptic to play. A fresh `id` per crossing so `.sensoryFeedback(trigger:)` fires every time.
    struct FeedbackEvent: Equatable {
        let id = UUID()
        let kind: LimitFeedback
    }

    private(set) var active: ShoppingSession?
    private(set) var limitState: LimitState = .noLimit
    private(set) var feedback: FeedbackEvent?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let analytics: any AnalyticsClient
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let logger = Logger(subsystem: "com.fernandocorreia.scanit", category: "session")

    init(context: ModelContext, analytics: any AnalyticsClient = LogAnalytics(), now: @escaping () -> Date = { .now }) {
        self.context = context
        self.analytics = analytics
        self.now = now
        loadActive()
    }

    // MARK: - Trip lifecycle

    /// Starts a trip. Any trip still marked active (there should be none) is abandoned first,
    /// so there is never more than one.
    @discardableResult
    func startTrip(store: Store?, limitMinor: Int?, currency: String) -> ShoppingSession {
        if let active { close(active, as: .abandoned) }
        let session = ShoppingSession(store: store, limitMinor: limitMinor, currency: currency, now: now())
        context.insert(session)
        store?.touch(now())
        save()
        active = session
        limitState = session.limitStatus.state
        feedback = nil
        analytics.track(.tripStarted(hasLimit: session.limitMinor != nil))
        return session
    }

    func cancelTrip() {
        guard let active else { return }
        close(active, as: .abandoned)
        save()
        self.active = nil
        limitState = .noLimit
    }

    // MARK: - Cart

    @discardableResult
    func addItem(
        code: ScannedCode, productName: String? = nil, quantity: Int = 1,
        unitPriceMinor: Int, priceSource: PriceSource
    ) -> CartItem? {
        guard let active else { return nil }
        let item = CartItem(
            code: code, productName: productName, quantity: quantity,
            unitPriceMinor: unitPriceMinor, priceSource: priceSource, now: now()
        )
        context.insert(item)
        item.session = active
        active.touch(now())
        save()
        refreshLimitState()
        return item
    }

    func update(_ item: CartItem, quantity: Int? = nil, unitPriceMinor: Int? = nil) {
        if let quantity { item.quantity = max(1, quantity) }
        if let unitPriceMinor {
            item.unitPriceMinor = unitPriceMinor
            item.priceSource = .manual
        }
        item.touch(now())
        save()
        refreshLimitState()
    }

    func remove(_ item: CartItem) {
        item.softDelete(now())
        save()
        refreshLimitState()
    }

    // MARK: - Internals

    private func loadActive() {
        let activeRaw = SessionStatus.active.rawValue
        var descriptor = FetchDescriptor<ShoppingSession>(
            predicate: #Predicate { $0.statusRaw == activeRaw && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        active = (try? context.fetch(descriptor))?.first
        limitState = active?.limitStatus.state ?? .noLimit
    }

    private func refreshLimitState() {
        let new = active?.limitStatus.state ?? .noLimit
        if let kind = LimitState.feedback(from: limitState, to: new) {
            feedback = FeedbackEvent(kind: kind)
        }
        limitState = new
    }

    private func close(_ session: ShoppingSession, as status: SessionStatus) {
        session.status = status
        session.endedAt = now()
        session.touch(now())
    }

    private func save() {
        do {
            try context.save()
        } catch {
            logger.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
