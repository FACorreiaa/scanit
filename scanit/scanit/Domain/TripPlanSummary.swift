import Foundation
import ScanItCore

/// Planned against spent for a trip started from the list (BACKLOG MEAL-005): the estimate at the
/// trip's store when it started, what the trip came to, and what was bought that the plan did not
/// have. On the finish sheet and in a past trip.
struct TripPlanSummary {
    /// The estimate when the trip started. `nil` when the store had none.
    let planned: Money?
    let spent: Money
    /// Lines the planned cost leaves out, for want of a price.
    let unpricedLines: Int
    /// Items no plan line answers, oldest first.
    let extras: [CartItem]

    /// `nil` for a trip that was not started from the list.
    init?(session: ShoppingSession) {
        guard let codes = session.plannedCodes, let texts = session.plannedTexts else { return nil }
        planned = session.plannedMinor.map { Money(amountMinor: $0, currency: session.currency) }
        spent = session.total
        unpricedLines = session.plannedUnpricedLines ?? 0
        let codeSet = Set(codes)
        extras = session.liveItems
            .filter { !Self.isOnPlan($0, codes: codeSet, texts: texts) }
            .sorted { $0.scannedAt < $1.scannedAt }
    }

    /// Positive when the trip cost more than planned. Buying more packs than planned shows here,
    /// not as an extra item.
    var difference: Money? {
        planned.map { Money(amountMinor: spent.amountMinor - $0.amountMinor, currency: spent.currency) }
    }

    /// "You spent €3,99 more than planned", "… less than planned", or "Spot on: exactly what you
    /// planned". `nil` without a planned cost.
    var differenceText: String? {
        guard let difference else { return nil }
        let amount = Money(amountMinor: abs(difference.amountMinor), currency: difference.currency).formatted()
        switch difference.amountMinor {
        case 0: return "Spot on: exactly what you planned"
        case 1...: return "You spent \(amount) more than planned"
        default: return "You spent \(amount) less than planned"
        }
    }

    var extrasTotal: Money {
        Money(amountMinor: extras.reduce(0) { $0 + $1.lineTotalMinor }, currency: spent.currency)
    }

    /// The list's own rule (`ShoppingList.tick`): the same code, or a typed line whose words all
    /// start a word of the product's name.
    static func isOnPlan(_ item: CartItem, codes: Set<String>, texts: [String]) -> Bool {
        if codes.contains(item.code) { return true }
        guard let name = item.productName else { return false }
        return texts.contains { ShoppingList.matches(line: $0, productName: name) }
    }
}

extension ShoppingSession {
    /// Freezes the plan on the trip when it starts.
    func keep(_ plan: TripPlan) {
        plannedCodes = plan.lines.compactMap(\.code)
        plannedTexts = plan.lines.filter { $0.code == nil }.map(\.text)
        plannedMinor = plan.cost?.amountMinor
        plannedUnpricedLines = plan.unpricedLines
    }
}
