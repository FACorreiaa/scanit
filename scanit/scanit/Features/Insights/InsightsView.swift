import ScanItCore
import SwiftData
import SwiftUI

/// Spending numbers (`DESIGN.md` → Insights catalogue, BACKLOG INS-103). Headline numbers are
/// stat tiles; spend by store and by category are single-series horizontal bars; products,
/// price changes and cheapest stores are lists. Until 3 trips are finished the screen shows how
/// far along the user is and what is coming.
struct InsightsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.analytics) private var analytics
    @Environment(\.showTrip) private var showTrip
    @Query(filter: #Predicate<ShoppingSession> { $0.statusRaw == "finished" && $0.deletedAt == nil })
    private var finishedTrips: [ShoppingSession]

    @Environment(BudgetStore.self) private var budgets
    @State private var period: InsightsCalculator.Period = .month
    @State private var isShowingAbout = false

    var body: some View {
        // Recomputed whenever finished trips change (the query drives the redraw).
        let calculator = InsightsSource.calculator(context: context)
        NavigationStack {
            Group {
                if calculator.hasEnoughData {
                    content(calculator)
                } else {
                    InsightsProgress(finished: finishedTrips.count)
                        .safeAreaInset(edge: .bottom) {
                            PrimaryActionBar(title: "Start shopping", identifier: "insightsStartShopping", action: showTrip)
                        }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                // The tab hides its navigation bar, so the screen carries its own one-button header.
                HStack {
                    Spacer()
                    Button("About", systemImage: "info.circle") { isShowingAbout = true }
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("insightsAbout")
                }
                .padding(.horizontal, 8)
                // Opaque up to the top edge: the list scrolls away under the header and the clock.
                .background {
                    (calculator.hasEnoughData ? Color(.systemGroupedBackground) : Color(.systemBackground))
                        .ignoresSafeArea(edges: .top)
                }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $isShowingAbout) {
            AboutSheet()
                .presentationDetents([.medium, .large])
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

            Section("Monthly budget") {
                let rows = budgetRows(calculator)
                ForEach(rows, id: \.currency) { spent in
                    MonthlyBudgetRow(
                        spent: spent, isPrimary: spent.currency == calculator.currency, showsCurrency: rows.count > 1
                    )
                }
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

            #if DEBUG
            OCRStatsSection(stats: OCRStats.current(context: context))
            #endif
        }
        .headerProminence(.increased)
        .contentMargins(.top, 8, for: .scrollContent)
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

    /// BUD-001: this month in every currency used or budgeted, the Insights currency first.
    private func budgetRows(_ calculator: InsightsCalculator) -> [Money] {
        let spends = InsightsSource.monthSpend(
            context: context, alsoIn: budgets.currencies + [calculator.currency], now: calculator.now,
            calendar: calculator.calendar
        )
        return spends.filter { $0.currency == calculator.currency } + spends.filter { $0.currency != calculator.currency }
    }

    private func productName(_ code: String) -> String {
        finishedTrips.lazy.flatMap(\.liveItems).first { $0.code == code }?.productName
            ?? ScannedCode(kind: .gtin, value: code).displayValue
    }
}

/// Before there is enough data: how many trips are done, and what each next trip unlocks. One
/// segment per required trip, so progress reads at a glance and in words.
private struct InsightsProgress: View {
    let finished: Int
    private let required = InsightsCalculator.minimumTrips

    var body: some View {
        // Centred when it fits, scrollable at the largest text sizes.
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Insights unlock after \(required) trips")
                            .font(.title2.bold())
                        HStack(spacing: 6) {
                            ForEach(0..<required, id: \.self) { index in
                                Capsule()
                                    .fill(index < finished ? Color.accentColor : Color(.tertiarySystemFill))
                                    .frame(height: 8)
                            }
                        }
                        Text("\(min(finished, required)) of \(required) trips done")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Insights unlock after \(required) trips")
                    .accessibilityValue("\(min(finished, required)) of \(required) trips done")
                    .accessibilityIdentifier("insightsProgress")

                    VStack(alignment: .leading, spacing: 20) {
                        Teaser(symbol: "banknote", text: "What you spend each week and month")
                        Teaser(symbol: "storefront", text: "Which stores get most of your money")
                        Teaser(symbol: "arrow.up.right.circle", text: "Which of your prices went up")
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private struct Teaser: View {
        let symbol: String
        let text: LocalizedStringKey
        /// One icon column, so the three lines start at the same x whatever the symbol's width.
        @ScaledMetric(relativeTo: .title3) private var iconWidth: CGFloat = 32

        var body: some View {
            Label {
                Text(text)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(Color.accentColor)
                    .font(.title3)
                    .frame(width: iconWidth)
            }
        }
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

#if DEBUG
/// Owner-only readout of the shelf-price field metrics (BACKLOG IOS-007) until PostHog arrives.
private struct OCRStatsSection: View {
    let stats: OCRStats

    var body: some View {
        Section("Shelf-price reading (debug)") {
            LabeledContent("Accepted unedited", value: share(stats.acceptedShare, of: stats.accepted))
            LabeledContent("Edited in the sheet", value: "\(stats.edited)")
            LabeledContent("Corrected later", value: share(stats.correctedShare, of: stats.corrected))
            LabeledContent("Items scanned", value: "\(stats.scanned)")
        }
        .monospacedDigit()
    }

    private func share(_ value: Double?, of count: Int) -> String {
        guard let value else { return "–" }
        return "\(count) · \(value.formatted(.percent.precision(.fractionLength(0))))"
    }
}
#endif
