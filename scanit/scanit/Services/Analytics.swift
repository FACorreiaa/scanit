import OSLog
import SwiftUI

/// Product events (`ARCHITECTURE.md` → Analytics). Never carries amounts or product names.
enum AnalyticsEvent: Equatable, Sendable {
    case appOpened
    case tripStarted(hasLimit: Bool)

    var name: String {
        switch self {
        case .appOpened: "app_opened"
        case .tripStarted: "trip_started"
        }
    }

    var properties: [String: String] {
        switch self {
        case .appOpened: [:]
        case .tripStarted(let hasLimit): ["has_limit": String(hasLimit)]
        }
    }
}

protocol AnalyticsClient: Sendable {
    func track(_ event: AnalyticsEvent)
}

/// Logs events locally. Replaced by a PostHog-backed client once ScanIt has its own PostHog
/// project key and Sentry DSN (BACKLOG FND-004); events must not go into another app's project.
struct LogAnalytics: AnalyticsClient {
    private static let logger = Logger(subsystem: "com.fernandocorreia.scanit", category: "analytics")

    func track(_ event: AnalyticsEvent) {
        Self.logger.info("event \(event.name, privacy: .public) \(event.properties, privacy: .public)")
    }
}

extension EnvironmentValues {
    @Entry var analytics: any AnalyticsClient = LogAnalytics()
}
