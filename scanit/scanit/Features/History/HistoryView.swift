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

    var body: some View {
        NavigationStack {
            Group {
                if trips.isEmpty {
                    ContentUnavailableView {
                        Label("No trips yet", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Finished trips show up here, grouped by month.")
                    }
                } else {
                    List {
                        ForEach(MonthGroup.group(trips)) { month in
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
                                        .accessibilityIdentifier("monthTotal")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
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

private struct TripRow: View {
    let trip: ShoppingSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.store?.name ?? "Trip")
                Text(trip.startedAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(trip.total.formatted())
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
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
        .sheet(item: $editing) { selection in
            EditItemSheet(item: selection.item, currency: trip.currency)
                .presentationDetents([.medium])
        }
    }
}
