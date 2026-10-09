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

    /// Ends the active trip and returns it for the summary. `nil` when there is nothing to finish.
    @discardableResult
    func finishTrip() -> ShoppingSession? {
        guard let active, !active.liveItems.isEmpty else { return nil }
        close(active, as: .finished)
        save()
        self.active = nil
        limitState = .noLimit
        let status = active.limitStatus
        analytics.track(.tripFinished(
            items: active.liveItems.reduce(0) { $0 + $1.quantity },
            underLimit: status.limitMinor == nil ? nil : status.state != .over
        ))
        return active
    }

    /// "Undo finish" on the summary: the trip becomes the active one again.
    func undoFinish(_ session: ShoppingSession) {
        guard session.status == .finished, active == nil else { return }
        session.status = .active
        session.endedAt = nil
        session.touch(now())
        save()
        active = session
        limitState = session.limitStatus.state
        feedback = nil
    }

    /// What the till actually charged (`DESIGN.md` §6); the gap is insight INS-09.
    func setTillTotal(_ session: ShoppingSession, minor: Int?) {
        session.tillTotalMinor = minor
        session.touch(now())
        save()
    }

    // MARK: - Cart

    /// Adds a confirmed item to the active trip and records its price for this store, so the
    /// next scan of the same product here is prefilled (BACKLOG IOS-008, IOS-009).
    @discardableResult
    func addItem(
        code: ScannedCode, productName: String? = nil, quantity: Int = 1,
        unitPriceMinor: Int, priceSource: PriceSource, symbology: Symbology? = nil
    ) -> CartItem? {
        guard let active else { return nil }
        let item = CartItem(
            code: code, productName: productName, quantity: max(1, quantity),
            unitPriceMinor: unitPriceMinor, priceSource: priceSource, now: now()
        )
        context.insert(item)
        item.session = active
        active.touch(now())
        recordPrice(code: code.value, unitPriceMinor: unitPriceMinor, source: priceSource, in: active)
        save()
        refreshLimitState()
        analytics.track(.itemScanned(priceSource: priceSource, symbology: symbology))
        return item
    }

    /// Works for items in the active trip and in past trips (History edits).
    func update(_ item: CartItem, quantity: Int? = nil, unitPriceMinor: Int? = nil) {
        if let quantity { item.quantity = max(1, quantity) }
        if let unitPriceMinor, unitPriceMinor != item.unitPriceMinor {
            item.unitPriceMinor = unitPriceMinor
            item.priceSource = .manual
            if let session = item.session {
                recordPrice(code: item.code, unitPriceMinor: unitPriceMinor, source: .manual, in: session)
            }
        }
        item.touch(now())
        item.session?.touch(now())
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

    /// Every confirmed price is a sighting, including a remembered price confirmed again: that
    /// refreshes "seen N days ago" and feeds price history (INS-06).
    private func recordPrice(code: String, unitPriceMinor: Int, source: PriceSource, in session: ShoppingSession) {
        guard let store = session.store else { return }
        let observation = PriceObservation(
            store: store, code: code,
            price: Money(amountMinor: unitPriceMinor, currency: session.currency),
            source: source, now: now()
        )
        context.insert(observation)
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
