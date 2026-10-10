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
    @State private var purchases = PurchaseStore()
    private let paywallPolicy: PaywallPolicy

    private let container: ModelContainer
    private let analytics: any AnalyticsClient = LogAnalytics()

    init() {
        // UI tests launch with `-ui-testing` to start from an empty, throwaway store.
        let inMemory = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        do {
            container = try ScanItSchema.container(inMemory: inMemory)
        } catch {
            fatalError("Could not open the ScanItNow store: \(error)")
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-demo-data") {
            DemoData.seed(container.mainContext)
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-demo-trip") {
            DemoData.seedActiveTrip(container.mainContext)
        }
        #endif
        _sessions = State(initialValue: SessionStore(context: container.mainContext, analytics: analytics))
        let lookup: any ProductLookup = inMemory
            ? FixedProductLookup(names: ["5601234567892": "Leite meio gordo", "4006381333931": "Pão de forma"])
            : OpenFoodFactsClient()
        _enricher = State(initialValue: ProductEnricher(context: container.mainContext, lookup: lookup))

        // Off until launch (REL-003). UI tests switch it on: `-paywall-enabled -paywall-free-trips N`.
        var policy = PaywallPolicy.launch
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-paywall-enabled") { policy.isEnabled = true }
        if let index = arguments.firstIndex(of: "-paywall-free-trips"), arguments.indices.contains(index + 1),
           let trips = Int(arguments[index + 1]) {
            policy.freeTripsPerMonth = trips
        }
        if let index = arguments.firstIndex(of: "-paywall-visible-history"), arguments.indices.contains(index + 1),
           let count = Int(arguments[index + 1]) {
            policy.visibleHistory = count
        }
        paywallPolicy = policy
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sessions)
                .environment(enricher)
                .environment(connectivity)
                .environment(purchases)
                .environment(\.paywallPolicy, paywallPolicy)
                .environment(\.analytics, analytics)
                // v1 ships free (docs/release.md): no StoreKit traffic until the paywall is switched on.
                .task { if paywallPolicy.isEnabled { await purchases.start() } }
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
