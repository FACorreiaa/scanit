import ScanItCore
import SwiftUI

/// "Saved this month" with a 6-month trend (BACKLOG SAVE-003, INS-14). The trend is one series in
/// the emphasis form: this month in the accent, earlier months in grey, both checked with the
/// dataviz validator against the tile surface in light and dark mode. Months above the baseline
/// saved, months below it paid more, and a month with nothing to compare draws no bar at all.
struct SavingsTile: View {
    /// Oldest first, this month last.
    let months: [MonthSaving]

    var body: some View {
        let current = months.last?.saving
        let summary = current.map {
            MonthSavingSummary($0, comparedBefore: months.dropLast().contains { $0.saving.hasComparison })
        }
        VStack(alignment: .leading, spacing: 4) {
            Text(summary?.title ?? "Saved this month")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(summary?.value ?? "—")
                .font(.title2.weight(.light))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(summary?.detail ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
            // A trend needs at least two points.
            if months.count { $0.saving.hasComparison } >= 2 {
                SavingsTrend(months: months)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("savingsTile")
    }
}

/// Six thin bars from a shared baseline, with the month under each. Values are not printed on the
/// bars; VoiceOver reads every month.
private struct SavingsTrend: View {
    let months: [MonthSaving]
    @ScaledMetric(relativeTo: .caption2) private var plotHeight: CGFloat = 44
    private let barWidth: CGFloat = 14

    var body: some View {
        let compared = months.filter(\.saving.hasComparison).map(\.saving.saving.amountMinor)
        let up = max(compared.max() ?? 0, 0)
        let down = max(-(compared.min() ?? 0), 0)
        // Space above and below the baseline in proportion to the biggest saving and overspend.
        let span = max(up + down, 1)
        let above = plotHeight * CGFloat(up) / CGFloat(span)

        VStack(spacing: 4) {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 1)
                    .offset(y: above - 0.5)
                // Top-aligned: every bar is offset from the plot's top edge, so a short bar must
                // not be centred against a tall one.
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(months.enumerated()), id: \.offset) { index, point in
                        bar(point, isCurrent: index == months.count - 1, above: above, span: span)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: plotHeight, alignment: .top)

            HStack(spacing: 0) {
                ForEach(Array(months.enumerated()), id: \.offset) { index, point in
                    Text(point.month.start, format: .dateTime.month(.abbreviated))
                        .font(.caption2)
                        .foregroundStyle(index == months.count - 1 ? .secondary : .tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last \(months.count) months")
        .accessibilityValue(months.map(spokenValue).joined(separator: ", "))
    }

    @ViewBuilder
    private func bar(_ point: MonthSaving, isCurrent: Bool, above: CGFloat, span: Int) -> some View {
        let minor = point.saving.saving.amountMinor
        if point.saving.hasComparison {
            // At least 2 pt, so a month that was even still shows it was compared.
            let length = max(2, plotHeight * CGFloat(abs(minor)) / CGFloat(span))
            let radius = min(4, length / 2)
            UnevenRoundedRectangle(
                topLeadingRadius: minor >= 0 ? radius : 0, bottomLeadingRadius: minor < 0 ? radius : 0,
                bottomTrailingRadius: minor < 0 ? radius : 0, topTrailingRadius: minor >= 0 ? radius : 0
            )
            .fill(isCurrent ? Color.accentColor : Color(.systemGray))
            .frame(width: barWidth, height: length)
            .offset(y: minor >= 0 ? above - length : above)
        } else {
            Color.clear.frame(width: barWidth, height: 0)
        }
    }

    private func spokenValue(_ point: MonthSaving) -> String {
        let month = point.month.start.formatted(.dateTime.month(.wide))
        guard point.saving.hasComparison else { return "\(month): nothing compared" }
        let minor = point.saving.saving.amountMinor
        let amount = Money(amountMinor: abs(minor), currency: point.saving.saving.currency).formatted()
        switch minor {
        case 1...: return "\(month): saved \(amount)"
        case 0: return "\(month): same as other stores"
        default: return "\(month): \(amount) more than other stores"
        }
    }
}

/// INS-13 summed per store for the month: where the things you bought were cheaper. Each row is that
/// store's own amount, never the month's total across stores.
struct SaveMostRows: View {
    let stores: [StoreMissedSaving]

    var body: some View {
        ForEach(stores, id: \.storeId) { store in
            LabeledContent {
                Text(store.missed.formatted()).monospacedDigit()
            } label: {
                Text(store.storeName ?? "Another store")
                Text("Cheaper for what you bought")
            }
            .accessibilityIdentifier("saveMost.\(store.storeName ?? store.storeId)")
        }
    }
}
