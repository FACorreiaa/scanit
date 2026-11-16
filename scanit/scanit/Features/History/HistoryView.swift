import ScanItCore
import SwiftData
import SwiftUI

/// Past trips grouped by month, with the month's total (BACKLOG IOS-011).
struct HistoryView: View {
    @Query(
        filter: #Predicate<ShoppingSession> { $0.statusRaw == "finished" && $0.deletedAt == nil },
        sort: \.startedAt,
        order: .reverse
    )
    private var trips: [ShoppingSession]

    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.paywallPolicy) private var paywall
    @Environment(\.showTrip) private var showTrip
    @State private var paywallReason: PaywallReasonItem?

    var body: some View {
        NavigationStack {
            Group {
                if trips.isEmpty {
                    ContentUnavailableView {
                        Label("No trips yet", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Finished trips show up here, grouped by month.")
                    } actions: {
                        Button("Start shopping", action: showTrip)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    let split = paywall.visibleTrips(trips, isUnlimited: purchases.isUnlimited)
                    let months = MonthGroup.group(split.visible)
                    List {
                        Section {
                            MonthSummary(month: months.first)
                                .listRowBackground(Color.clear)
                        }
                        ForEach(months) { month in
                            Section {
                                ForEach(month.trips, id: \.id) { trip in
                                    NavigationLink(value: TripRoute(id: trip.id)) {
                                        TripRow(trip: trip)
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(month.monthStart, format: .dateTime.month(.wide).year())
                                    Spacer()
                                    Text(month.totals.map { $0.formatted() }.joined(separator: " · "))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .accessibilityIdentifier("monthTotal")
                                }
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .textCase(nil)
                            }
                        }
                        if split.hiddenCount > 0 {
                            Section {
                                Button {
                                    paywallReason = PaywallReasonItem(reason: .hiddenHistory(count: split.hiddenCount))
                                } label: {
                                    Label(
                                        split.hiddenCount == 1 ? "1 older trip" : "\(split.hiddenCount) older trips",
                                        systemImage: "lock"
                                    )
                                }
                                .accessibilityIdentifier("lockedTrips")
                            } footer: {
                                Text("Kept safely. Unlock to see them again.")
                            }
                        }
                    }
                }
            }
            // The hidden bar leaves no scroll edge effect, so the list needs a backdrop under the clock.
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: 0)
                    .background { (trips.isEmpty ? Color(.systemBackground) : Color(.systemGroupedBackground)).ignoresSafeArea(edges: .top) }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(item: $paywallReason) { item in
                PaywallSheet(reason: item.reason)
                    .presentationDetents([.medium, .large])
            }
            .navigationDestination(for: TripRoute.self) { route in
                if let trip = trips.first(where: { $0.id == route.id }) {
                    TripDetailView(trip: trip)
                }
            }
        }
    }
}

/// Navigation value: SwiftData models are routed by id, not by reference.
struct TripRoute: Hashable {
    let id: UUID
}

/// The screen's headline: what this month has cost so far. It answers the question people open
/// History with before they go looking for a single trip.
private struct MonthSummary: View {
    /// The newest month with trips; only counted when it is the current month.
    let month: MonthGroup?

    var body: some View {
        let current = month.flatMap { Calendar.current.isDate($0.monthStart, equalTo: .now, toGranularity: .month) ? $0 : nil }
        VStack(alignment: .leading, spacing: 4) {
            Text("This month")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(current?.totals.map { $0.formatted() }.joined(separator: " · ") ?? "Nothing yet")
                .font(.largeTitle.weight(.light))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(tripCountText(current?.trips.count ?? 0))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private func tripCountText(_ count: Int) -> String {
        switch count {
        case 0: "No trips this month yet"
        case 1: "1 trip this month"
        default: "\(count) trips this month"
        }
    }
}

private struct TripRow: View {
    let trip: ShoppingSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.store?.name ?? "Trip")
                    .font(.body.weight(.medium))
                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(trip.total.formatted())
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                if let limitText {
                    Text(limitText)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(trip.limitStatus.state == .over ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detailText: String {
        let date = trip.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let count = trip.itemCount
        return "\(date) · \(count == 1 ? "1 item" : "\(count) items")"
    }

    /// Colour is never the only signal (`DESIGN.md` → Accessibility), so the result is words.
    private var limitText: String? {
        guard let remaining = trip.limitStatus.remainingMinor else { return nil }
        guard remaining < 0 else { return "Under limit" }
        return "\(Money(amountMinor: -remaining, currency: trip.currency).formatted()) over"
    }
}

/// One past trip. Prices and quantities can still be fixed afterwards.
struct TripDetailView: View {
    @Environment(SessionStore.self) private var sessions
    let trip: ShoppingSession
    @State private var editing: CartItemSelection?

    var body: some View {
        List {
            Section {
                TripTotalHeader(total: trip.total, limit: trip.limit, status: trip.limitStatus)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .listRowBackground(Color.clear)
            }
            if let till = trip.tillTotalMinor {
                Section {
                    LabeledContent("Till total", value: Money(amountMinor: till, currency: trip.currency).formatted())
                        .monospacedDigit()
                }
            }
            Section {
                ForEach(trip.liveItems.sorted { $0.scannedAt > $1.scannedAt }, id: \.id) { item in
                    Button {
                        editing = CartItemSelection(item: item)
                    } label: {
                        CartItemRow(item: item, currency: trip.currency)
                    }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            sessions.remove(item)
                        }
                    }
                }
            }
        }
        .navigationTitle(trip.store?.name ?? "Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                TripShareLink(session: trip)
            }
        }
        .sheet(item: $editing) { selection in
            EditItemSheet(item: selection.item, currency: trip.currency)
                .presentationDetents([.medium])
        }
    }
}
