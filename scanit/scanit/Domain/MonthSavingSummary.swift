import Foundation
import ScanItCore

/// What the "Saved this month" tile on Insights says (BACKLOG SAVE-003). The number is INS-14
/// (`DESIGN.md` → Insights catalogue); the wording follows the trip's saving (SAVE-002): never a
/// minus sign under "Saved", and "nothing to compare" is not the same as saving 0.
struct MonthSavingSummary: Equatable {
    let title: String
    let value: String
    let detail: String

    /// - Parameters:
    ///   - month: INS-14 for this calendar month.
    ///   - comparedBefore: whether any earlier month in the trend had something to compare.
    init(_ month: PeriodSaving, comparedBefore: Bool) {
        guard month.hasComparison else {
            title = "Saved this month"
            value = "—"
            detail = comparedBefore ? "Nothing compared yet this month" : "Needs prices from a second store"
            return
        }
        let trips = month.comparedTrips == 1 ? "1 trip" : "\(month.comparedTrips) trips"
        let amount = Money(amountMinor: abs(month.saving.amountMinor), currency: month.saving.currency).formatted()
        switch month.saving.amountMinor {
        case 1...:
            title = "Saved this month"
            detail = "Vs other stores · \(trips)"
        case 0:
            title = "Saved this month"
            detail = "Same as other stores · \(trips)"
        default:
            title = "Paid more this month"
            detail = "Than other stores · \(trips)"
        }
        value = amount
    }
}
