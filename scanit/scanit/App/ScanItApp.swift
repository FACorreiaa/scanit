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
    @State private var reviews: ReviewPrompter
    @State private var budgets: BudgetStore
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
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-demo-meals") {
            DemoData.seedMeals(container.mainContext)
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-demo-usd-trip") {
            DemoData.seedForeignTrip(container.mainContext)
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-demo-trip") {
            DemoData.seedActiveTrip(container.mainContext)
        }
        // Stands in for `StartShoppingIntent`, which UI tests cannot run.
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-start-shopping") {
            ShortcutActions.shared.requestStartShopping()
        }
        #endif
        // UI tests run without a Live Activity: it would outlive the throwaway store.
        let wantsActivity = !inMemory || ProcessInfo.processInfo.arguments.contains("-ui-testing-live-activity")
        let liveActivity = wantsActivity ? TripActivityController() : nil
        _sessions = State(initialValue: SessionStore(
            context: container.mainContext, analytics: analytics,
            onTripChange: { liveActivity?.sync($0) }
        ))
        let lookup: any ProductLookup = inMemory
            ? FixedProductLookup(names: ["5601234567892": "Leite meio gordo", "4006381333931": "Pão de forma"])
            : OpenFoodFactsClient()
        _enricher = State(initialValue: ProductEnricher(context: container.mainContext, lookup: lookup))
        // UI tests never ask for a rating (debug builds always show the sheet) and keep the
        // simulator's real defaults untouched.
        if inMemory {
            let suite = "scanit.uitesting"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            _reviews = State(initialValue: ReviewPrompter(defaults: defaults, isSuppressed: true))
            _budgets = State(initialValue: BudgetStore(defaults: defaults))
        } else {
            _reviews = State(initialValue: ReviewPrompter())
            _budgets = State(initialValue: BudgetStore())
        }

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
                .environment(reviews)
                .environment(budgets)
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
