import ScanItCore
import SwiftUI

/// The hero total and limit bar (`DESIGN.md` §3 and §5). Shared by the trip screen and,
/// later, the scanner HUD, so the number looks the same everywhere.
struct TripTotalHeader: View {
    let total: Money
    let limit: Money?
    let status: LimitStatus
    /// Smaller total for the scanner HUD, where the camera needs the room.
    var compact = false
    /// Speak the new total to VoiceOver after every change. Only one header on screen should do
    /// this: the trip screen stays alive under the scanner, so it is the one that announces.
    var announcesChanges = false

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 48
    @ScaledMetric(relativeTo: .title) private var compactSize: CGFloat = 28

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            Text(total.formatted())
                .font(.system(size: compact ? compactSize : heroSize, weight: .light))
                .monospacedDigit()
                // A truncated amount is a wrong amount ("€1 234,…"). Shrinking is the lesser evil
                // for one line of money at the largest text sizes; it never truncates.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: Double(total.amountMinor)))

            if let limit, let progress = status.progress {
                VStack(spacing: 8) {
                    ProgressView(value: min(progress, 1))
                        .tint(status.state.tint)
                    // Side by side when it fits, stacked at large text sizes.
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            remainingLabel
                            Spacer()
                            limitLabel(limit)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            remainingLabel
                            limitLabel(limit)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.subheadline)
                    .monospacedDigit()
                }
            }
        }
        .animation(.snappy, value: total)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .onChange(of: total) { _, _ in
            guard announcesChanges else { return }
            AccessibilityNotification.Announcement(accessibilityText).post()
        }
    }

    private var remainingLabel: some View {
        Text(remainingText)
            .lineLimit(1)
            .foregroundStyle(status.state == .over ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
    }

    private func limitLabel(_ limit: Money) -> some View {
        Text("of \(limit.formatted())")
            .lineLimit(1)
            .foregroundStyle(.secondary)
    }

    private var remainingText: String {
        guard let remaining = status.remainingMinor else { return "" }
        let amount = Money(amountMinor: abs(remaining), currency: total.currency).formatted()
        return status.state == .over ? "\(amount) over" : "\(amount) left"
    }

    private var accessibilityText: String {
        guard let limit else { return "Total \(total.formatted())" }
        return "Total \(total.formatted()), \(remainingText) of \(limit.formatted())"
    }
}

extension LimitState {
    /// Amber and red are reserved for the limit (`DESIGN.md` → Do not).
    var tint: Color {
        switch self {
        case .noLimit, .ok: .accentColor
        case .near: .orange
        case .over: .red
        }
    }
}

#Preview("States") {
    VStack(spacing: 40) {
        TripTotalHeader(total: Money(amountMinor: 4280, currency: "EUR"), limit: Money(amountMinor: 6000, currency: "EUR"),
                        status: LimitStatus(totalMinor: 4280, limitMinor: 6000))
        TripTotalHeader(total: Money(amountMinor: 5390, currency: "EUR"), limit: Money(amountMinor: 6000, currency: "EUR"),
                        status: LimitStatus(totalMinor: 5390, limitMinor: 6000))
        TripTotalHeader(total: Money(amountMinor: 6340, currency: "EUR"), limit: Money(amountMinor: 6000, currency: "EUR"),
                        status: LimitStatus(totalMinor: 6340, limitMinor: 6000))
        TripTotalHeader(total: Money(amountMinor: 4280, currency: "EUR"), limit: nil,
                        status: LimitStatus(totalMinor: 4280, limitMinor: nil))
    }
    .padding(16)
}
