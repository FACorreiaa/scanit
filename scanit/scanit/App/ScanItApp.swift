import SwiftData
import SwiftUI

@main
struct ScanItApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasReportedOpen = false
    @State private var hasStartedConnectivity = false
    @State private var sessions: SessionStore
    @State private var enricher: ProductEnricher
    @State private var connectivity = ConnectivityMonitor()

    private let container: ModelContainer
    private let analytics: any AnalyticsClient = LogAnalytics()

    init() {
        // UI tests launch with `-ui-testing` to start from an empty, throwaway store.
        let inMemory = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        do {
            container = try ScanItSchema.container(inMemory: inMemory)
        } catch {
            fatalError("Could not open the ScanIt store: \(error)")
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-demo-data") {
            DemoData.seed(container.mainContext)
        }
        #endif
        _sessions = State(initialValue: SessionStore(context: container.mainContext, analytics: analytics))
        let lookup: any ProductLookup = inMemory
            ? FixedProductLookup(names: ["5601234567892": "Leite meio gordo"])
            : OpenFoodFactsClient()
        _enricher = State(initialValue: ProductEnricher(context: container.mainContext, lookup: lookup))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sessions)
                .environment(enricher)
                .environment(connectivity)
                .environment(\.analytics, analytics)
                .task {
                    guard !hasStartedConnectivity else { return }
                    hasStartedConnectivity = true
                    connectivity.onReconnect { [enricher] in Task { await enricher.flush() } }
                    connectivity.start()
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Anything queued while the app was closed or offline.
            Task { await enricher.flush() }
            guard !hasReportedOpen else { return }
            hasReportedOpen = true
            analytics.track(.appOpened)
        }
    }
}
