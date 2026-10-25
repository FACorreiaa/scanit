import SwiftData
import SwiftUI

/// Three tabs (`DESIGN.md` → Information architecture). Tab roots carry no large title: the tab
/// bar already names them, so each screen opens on its content.
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
        .environment(\.showTrip) { selection = .trip }
    }
}

extension EnvironmentValues {
    /// Switches to the Trip tab, for empty states whose next step is to go shopping.
    @Entry var showTrip: () -> Void = {}
}

#Preview {
    let container = try! ScanItSchema.container(inMemory: true)
    RootView()
        .environment(SessionStore(context: container.mainContext))
        .environment(ProductEnricher(context: container.mainContext, lookup: FixedProductLookup(names: [:])))
        .environment(ConnectivityMonitor())
        .environment(PurchaseStore())
        .environment(ReviewPrompter(defaults: UserDefaults(suiteName: "scanit.preview") ?? .standard, isSuppressed: true))
        .modelContainer(container)
}
