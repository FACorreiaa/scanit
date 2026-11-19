import Foundation
import ScanItCore

/// What a shared trip card says (BACKLOG ADD-002). Totals only: what was bought stays on the phone.
nonisolated struct TripShareContent: Equatable, Sendable {
    let storeName: String?
    let date: Date
    let total: Money
    let limit: Money?
    let status: LimitStatus
    /// Units, not lines: 2 × milk counts as 2.
    let itemCount: Int
    /// The trip's saving vs other stores (SAVE-002). Only a real saving goes on the card.
    let saving: Money?

    init(storeName: String?, date: Date, total: Money, limit: Money?, itemCount: Int, saving: Money? = nil) {
        self.storeName = storeName
        self.date = date
        self.total = total
        self.limit = limit
        self.status = LimitStatus(totalMinor: total.amountMinor, limitMinor: limit?.amountMinor)
        self.itemCount = itemCount
        self.saving = saving.flatMap { $0.amountMinor > 0 ? $0 : nil }
    }

    init(session: ShoppingSession, saving: TripSavingSummary? = nil) {
        self.init(
            storeName: session.store?.name, date: session.endedAt ?? session.startedAt,
            total: session.total, limit: session.limit, itemCount: session.itemCount, saving: saving?.saving
        )
    }

    /// "Saved €0,60 vs other stores". `nil` unless the trip saved something.
    @MainActor var savingLine: String? {
        saving.map { "Saved \($0.formatted()) vs other stores" }
    }

    /// The note under the share button: what the picture shows, and that the products stay private.
    static func footer(includesSaving: Bool) -> String {
        includesSaving
            ? "A picture of your total, limit and saving. It doesn't show what you bought."
            : "A picture of your total and limit. It doesn't show what you bought."
    }

    /// "€17,20 under my €60,00 limit". `nil` for a trip without a limit.
    @MainActor var result: String? {
        guard let limit, let remaining = status.remainingMinor else { return nil }
        let amount = Money(amountMinor: abs(remaining), currency: total.currency).formatted()
        if remaining == 0 { return "Right on my \(limit.formatted()) limit" }
        return "\(amount) \(remaining < 0 ? "over" : "under") my \(limit.formatted()) limit"
    }

    var isOver: Bool { status.state == .over }

    /// How full the limit bar is, capped at full.
    var progress: Double? { status.progress.map { min(max($0, 0), 1) } }

    var items: String { itemCount == 1 ? "1 item" : "\(itemCount) items" }

    /// The line next to the image in the share sheet and in apps that show text with it.
    @MainActor var caption: String {
        let place = storeName.map { " at \($0)" } ?? ""
        return "\(total.formatted())\(place), tracked with ScanItNow"
    }
}
