import Foundation
import ScanItCore

/// What a finished trip's saving says, on the finish sheet, in History and on the share card
/// (BACKLOG SAVE-002). The numbers are INS-12 and INS-13 (`DESIGN.md` → Insights catalogue).
struct TripSavingSummary: Equatable {
    /// INS-12: positive when the trip cost less than the same products elsewhere.
    let saving: Money
    /// INS-13 at the one store that would have saved the most (not the trip's total, which can be
    /// spread over several stores).
    let missed: Money
    /// That store's name, when it has one.
    let missedAt: String?
    /// Products that had a price from another store.
    let compared: Int
    /// Products that could be compared at all (real GTINs).
    let products: Int

    init(saving: Money, missed: Money, missedAt: String?, compared: Int, products: Int) {
        self.saving = saving
        self.missed = missed
        self.missedAt = missedAt
        self.compared = compared
        self.products = products
    }

    /// `nil` when no product had a price from another store: there is nothing to say.
    init?(_ trip: TripSaving) {
        let compared = trip.lines.count - trip.unpricedLines
        guard compared > 0 else { return nil }
        let top = trip.missedByStore.first
        self.init(
            saving: trip.saving, missed: top?.missed ?? Money(amountMinor: 0, currency: trip.saving.currency),
            missedAt: top?.storeName, compared: compared, products: trip.lines.count
        )
    }

    /// Finish sheet: "Saved €0,60 vs other stores", "€1,46 more than other stores", or
    /// "Same as other stores". Never a minus sign under "Saved".
    var text: String {
        switch saving.amountMinor {
        case 0: return "Same as other stores"
        case 1...: return "Saved \(saving.formatted()) vs other stores"
        default: return "\(amount(-saving.amountMinor)) more than other stores"
        }
    }

    /// History row, where space is short.
    var shortText: String {
        switch saving.amountMinor {
        case 0: return "Same as elsewhere"
        case 1...: return "Saved \(saving.formatted())"
        default: return "\(amount(-saving.amountMinor)) more than elsewhere"
        }
    }

    /// "Could have saved €1,46 at Lidl", only when another store was cheaper for something.
    var missedText: String? {
        guard missed.amountMinor > 0 else { return nil }
        return "Could have saved \(missed.formatted()) \(missedAt.map { "at \($0)" } ?? "elsewhere")"
    }

    /// "Compared on 3 of 4 products", only when some products had no price elsewhere.
    var coverageText: String? {
        compared < products ? "Compared on \(compared) of \(products) products" : nil
    }

    var isSaving: Bool { saving.amountMinor > 0 }

    private func amount(_ minor: Int) -> String {
        Money(amountMinor: minor, currency: saving.currency).formatted()
    }
}
