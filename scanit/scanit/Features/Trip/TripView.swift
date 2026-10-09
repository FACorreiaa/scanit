import SwiftUI

/// Trip tab: the active trip, or an empty state with a big Start button.
struct TripView: View {
    @Environment(SessionStore.self) private var sessions
    @State private var isStarting = false

    var body: some View {
        NavigationStack {
            if let active = sessions.active {
                ActiveTripView(session: active)
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
    }
}
