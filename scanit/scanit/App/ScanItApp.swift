import SwiftData
import SwiftUI

@main
struct ScanItApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasReportedOpen = false
    @State private var sessions: SessionStore

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
        _sessions = State(initialValue: SessionStore(context: container.mainContext, analytics: analytics))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sessions)
                .environment(\.analytics, analytics)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !hasReportedOpen else { return }
            hasReportedOpen = true
            analytics.track(.appOpened)
        }
    }
}
