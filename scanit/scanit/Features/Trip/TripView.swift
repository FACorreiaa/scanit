import SwiftUI

/// Trip tab: the active trip, or an empty state with a big Start button. Owns the finish
/// summary because the active-trip screen disappears the moment the trip ends.
struct TripView: View {
    @Environment(SessionStore.self) private var sessions
    @State private var isStarting = false
    @State private var finished: FinishedTrip?

    var body: some View {
        NavigationStack {
            if let active = sessions.active {
                ActiveTripView(session: active) { finished = FinishedTrip(session: $0) }
            } else {
                ContentUnavailableView {
                    Label("No trip in progress", systemImage: "cart")
                } description: {
                    Text("Scan products as you shop and watch your total against your limit.")
                } actions: {
                    Button("Start a trip") { isStarting = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("openStartTrip")
                }
                .navigationTitle("Trip")
            }
        }
        .sheet(isPresented: $isStarting) {
            StartTripSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $finished) { trip in
            TripSummarySheet(session: trip.session)
        }
    }
}

struct FinishedTrip: Identifiable {
    let session: ShoppingSession
    var id: UUID { session.id }
}
