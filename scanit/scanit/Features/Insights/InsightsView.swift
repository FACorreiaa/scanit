import ScanItCore
import SwiftData
import SwiftUI

/// Spending numbers (`DESIGN.md` → Insights catalogue, BACKLOG INS-103). Headline numbers are
/// stat tiles; spend by store and by category are single-series horizontal bars; products,
/// price changes and cheapest stores are lists. Nothing shows until 3 trips are finished.
struct InsightsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.analytics) private var analytics
    @Query(filter: #Predicate<ShoppingSession> { $0.statusRaw == "finished" && $0.deletedAt == nil })
    private var finishedTrips: [ShoppingSession]

    @State private var period: InsightsCalculator.Period = .month

    var body: some View {
        // Recomputed whenever finished trips change (the query drives the redraw).
        let calculator = InsightsSource.calculator(context: context)
        NavigationStack {
            Group {
                if calculator.hasEnoughData {
                    content(calculator)
                } else {
                    ContentUnavailableView {
                        Label("Insights after 3 trips", systemImage: "chart.bar")
                    } description: {
                        Text("Once you've finished 3 trips you'll see what you spend, where, and which prices went up.")
                    }
                }
            }
            .navigationTitle("Insights")
        }
        .onAppear { analytics.track(.insightsViewed) }
    }

    private func content(_ calculator: InsightsCalculator) -> some View {
        let interval = calculator.interval(period)
        let stores = calculator.spendByStore(in: interval)
        let categories = calculator.categorySplit(in: interval)
        let products = calculator.topProducts(in: interval, limit: 5)
        let risers = calculator.priceChanges().filter { $0.percent > 0 }.prefix(5)
        let cheapest = calculator.cheapestStores().prefix(5)

        return List {
            Section {
                HeadlineTiles(calculator: calculator)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Picker("Period", selection: $period) {
                    Text("This week").tag(InsightsCalculator.Period.week)
                    Text("This month").tag(InsightsCalculator.Period.month)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if !stores.isEmpty {
                Section("By store") {
                    SpendBars(rows: stores.map { ($0.storeName ?? "Other", $0.total) })
                }
            }

            if !categories.isEmpty {
                Section("By category") {
                    SpendBars(rows: categories.map { (InsightsSource.categoryTitle($0.category), $0.total) })
                }
            }

            if !products.isEmpty {
                Section("Top products") {
                    ForEach(products, id: \.code) { product in
                        LabeledContent {
                            Text(product.total.formatted()).monospacedDigit()
                        } label: {
                            Text(product.name ?? ScannedCode(kind: .gtin, value: product.code).displayValue)
                            Text("\(product.quantity) bought")
                        }
                    }
                }
            }

            if !risers.isEmpty {
                Section("Prices that went up") {
                    ForEach(Array(risers), id: \.code) { change in
                        LabeledContent {
                            Text("+\(change.percent, format: .number.precision(.fractionLength(0)))%")
                                .monospacedDigit()
                        } label: {
                            Text(productName(change.code))
                            Text("\(change.first.priceMinor.money(change.first.currency)) → \(change.latest.priceMinor.money(change.latest.currency)) at \(change.storeName ?? "store")")
                        }
                    }
                }
            }

            if let basket = calculator.basketInflation() {
                Section {
                    LabeledContent {
                        Text(signedPercent(basket.ratePercent)).monospacedDigit()
                    } label: {
                        Text("Your regular basket")
                        Text("Over 90 days · \(Int(basket.coveragePercent.rounded()))% of spend")
                    }
                    if let gap = calculator.tillGap() {
                        LabeledContent {
                            Text(signedMoney(gap.mean)).monospacedDigit()
                        } label: {
                            Text("Till vs scanned")
                            Text(gap.trips == 1 ? "On 1 trip" : "Average over \(gap.trips) trips")
                        }
                    }
                } header: {
                    Text("Your prices")
                }
            } else if let gap = calculator.tillGap() {
                Section("Your prices") {
                    LabeledContent {
                        Text(signedMoney(gap.mean)).monospacedDigit()
                    } label: {
                        Text("Till vs scanned")
                        Text(gap.trips == 1 ? "On 1 trip" : "Average over \(gap.trips) trips")
                    }
                }
            }

            if !cheapest.isEmpty {
                Section("Cheapest for things you buy often") {
                    ForEach(Array(cheapest), id: \.code) { row in
                        LabeledContent {
                            Text("Save \(row.saving.formatted())").monospacedDigit()
                        } label: {
                            Text(row.name ?? ScannedCode(kind: .gtin, value: row.code).displayValue)
                            Text("\(row.cheapest.storeName ?? "One store") vs \(row.dearest.storeName ?? "another")")
                        }
                    }
                }
            }
        }
    }

    private func signedPercent(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == 0 { return "No change" }
        return "\(rounded > 0 ? "+" : "−")\(abs(rounded).formatted(.number.precision(.fractionLength(1))))%"
    }

    private func signedMoney(_ money: Money) -> String {
        let amount = Money(amountMinor: abs(money.amountMinor), currency: money.currency).formatted()
        return money.amountMinor == 0 ? "Matches" : "\(money.amountMinor > 0 ? "+" : "−")\(amount)"
    }

    private func productName(_ code: String) -> String {
        finishedTrips.lazy.flatMap(\.liveItems).first { $0.code == code }?.productName
            ?? ScannedCode(kind: .gtin, value: code).displayValue
    }
}

/// INS-01/02/03 as stat tiles: a hero number with one line of context each.
private struct HeadlineTiles: View {
    let calculator: InsightsCalculator

    var body: some View {
        let month = calculator.spend(.month)
        let week = calculator.spend(.week)
        let adherence = calculator.limitAdherence()
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatTile(title: "This month", value: month.current.formatted(), detail: deltaText(month, period: "last month"))
                StatTile(title: "This week", value: week.current.formatted(), detail: deltaText(week, period: "last week"))
            }
            GridRow {
                StatTile(title: "Average trip", value: calculator.averageTrip()?.formatted() ?? "—", detail: "Last 90 days")
                StatTile(
                    title: "Under limit",
                    value: adherence.withLimit == 0 ? "—" : "\(adherence.under) of \(adherence.withLimit)",
                    detail: adherence.withLimit == 0 ? "No trips with a limit" : "Trips with a limit"
                )
            }
        }
    }

    private func deltaText(_ spend: PeriodSpend, period: String) -> String {
        guard let percent = spend.deltaPercent else { return "Nothing \(period)" }
        let rounded = Int(percent.rounded())
        if rounded == 0 { return "Same as \(period)" }
        return "\(rounded > 0 ? "+" : "−")\(abs(rounded))% vs \(period)"
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.light))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

/// One series, so one colour (the accent, validated for both modes), no legend. Plain rows, not
/// a chart engine: a short ranked list reads best as name, bar, value. The bar is scaled to the
/// biggest row; the number is always printed, so nothing depends on judging bar length.
private struct SpendBars: View {
    let rows: [(label: String, total: Money)]
    @ScaledMetric(relativeTo: .body) private var barHeight: CGFloat = 8

    var body: some View {
        let biggest = max(rows.map(\.total.amountMinor).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.label)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text(row.total.formatted())
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geometry in
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(barHeight, geometry.size.width * CGFloat(row.total.amountMinor) / CGFloat(biggest)))
                    }
                    .frame(height: barHeight)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.label)
                .accessibilityValue(row.total.formatted())
            }
        }
        .padding(.vertical, 8)
    }
}

private extension Int {
    func money(_ currency: String) -> String {
        Money(amountMinor: self, currency: currency).formatted()
    }
}
