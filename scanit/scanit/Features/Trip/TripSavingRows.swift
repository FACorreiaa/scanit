import ScanItCore
import SwiftUI

/// The trip's saving vs other stores (BACKLOG SAVE-002), on the finish sheet and in a past trip.
/// Words carry the meaning; colour only repeats it.
struct TripSavingRows: View {
    let saving: TripSavingSummary

    var body: some View {
        Label {
            Text(saving.text)
                .monospacedDigit()
                .accessibilityIdentifier("tripSaving")
        } icon: {
            Image(systemName: saving.isSaving ? "arrow.down.circle.fill" : "equal.circle")
                .foregroundStyle(saving.isSaving ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
        }
        if let missed = saving.missedText {
            Label {
                Text(missed)
                    .monospacedDigit()
                    .accessibilityIdentifier("tripMissedSaving")
            } icon: {
                Image(systemName: "storefront")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }
}
