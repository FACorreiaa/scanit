import SwiftUI

@main
struct ScanItApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasReportedOpen = false

    private let analytics: any AnalyticsClient = LogAnalytics()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.analytics, analytics)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, !hasReportedOpen else { return }
            hasReportedOpen = true
            analytics.track(.appOpened)
        }
    }
}
