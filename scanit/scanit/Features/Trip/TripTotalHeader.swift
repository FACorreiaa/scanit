import ScanItCore
import SwiftUI

/// The hero total and limit bar (`DESIGN.md` §3 and §5). Shared by the trip screen and,
/// later, the scanner HUD, so the number looks the same everywhere.
struct TripTotalHeader: View {
    let total: Money
    let limit: Money?
    let status: LimitStatus

    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 48

    var body: some View {
        VStack(spacing: 12) {
            Text(total.formatted())
                .font(.system(size: heroSize, weight: .light))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(total.amountMinor)))

            if let limit, let progress = status.progress {
                VStack(spacing: 8) {
                    ProgressView(value: min(progress, 1))
                        .tint(status.state.tint)
                    HStack {
                        Text(remainingText)
                            .foregroundStyle(status.state == .over ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        Spacer()
                        Text("of \(limit.formatted())")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .monospacedDigit()
                }
            }
        }
        .animation(.snappy, value: total)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
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
