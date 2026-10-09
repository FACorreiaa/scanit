import SwiftUI

/// Trip tab. Empty state until a trip exists; the start sheet is BACKLOG IOS-003 and the
/// active-trip screen IOS-004.
struct TripView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No trip in progress", systemImage: "cart")
            } description: {
                Text("Start a trip, scan products as you shop, and watch your total against your limit.")
            }
            .navigationTitle("Trip")
        }
    }
}

#Preview {
    TripView()
}
