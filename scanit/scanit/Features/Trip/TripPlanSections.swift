import ScanItCore
import SwiftUI

/// Planned against spent, and what was bought off the plan (BACKLOG MEAL-005). On the finish sheet
/// and in a past trip, for trips started from the list.
struct TripPlanSections: View {
    let summary: TripPlanSummary
    let currency: String

    var body: some View {
        Section {
            if let planned = summary.planned {
                LabeledContent("You planned", value: planned.formatted())
                    .monospacedDigit()
                    .accessibilityIdentifier("tripPlanned")
            }
            if let text = summary.differenceText {
                Text(text)
                    .monospacedDigit()
                    .accessibilityIdentifier("tripVsPlan")
            }
            if summary.extras.isEmpty {
                Text("You stuck to your list")
                    .accessibilityIdentifier("tripOnPlan")
            }
        } header: {
            Text("Your plan")
        } footer: {
            if let footer { Text(footer) }
        }

        if !summary.extras.isEmpty {
            Section {
                ForEach(summary.extras, id: \.id) { item in
                    CartItemRow(item: item, currency: currency)
                        .accessibilityIdentifier("offPlan.\(item.productName ?? item.code)")
                }
            } header: {
                Text("Not on your list")
            } footer: {
                if summary.extras.count > 1 {
                    Text("\(summary.extrasTotal.formatted()) on things that weren't on your list.")
                }
            }
        }
    }

    private var footer: String? {
        guard summary.planned != nil else {
            return "You hadn't seen prices at this store yet, so there's nothing to compare with."
        }
        switch summary.unpricedLines {
        case 0: return nil
        case 1: return "1 thing on your list had no price here yet, so it isn't counted."
        default: return "\(summary.unpricedLines) things on your list had no price here yet, so they aren't counted."
        }
    }
}
