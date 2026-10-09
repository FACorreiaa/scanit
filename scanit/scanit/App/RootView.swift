import SwiftData
import SwiftUI

/// Three tabs (`DESIGN.md` → Information architecture). Settings live behind the avatar in
/// the History and Insights headers, not in a tab.
struct RootView: View {
    enum TabID: Hashable {
        case trip, history, insights
    }

    @State private var selection: TabID = .trip

    var body: some View {
        TabView(selection: $selection) {
            Tab("Trip", systemImage: "cart", value: .trip) {
                TripView()
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: .history) {
                HistoryView()
            }
            Tab("Insights", systemImage: "chart.bar", value: .insights) {
                InsightsView()
            }
        }
    }
}

#Preview {
    let container = try! ScanItSchema.container(inMemory: true)
    RootView()
        .environment(SessionStore(context: container.mainContext))
        .modelContainer(container)
}
