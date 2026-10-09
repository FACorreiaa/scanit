import OSLog
import ScanItCore
import SwiftUI

/// Product events (`ARCHITECTURE.md` → Analytics). Never carries amounts or product names.
enum AnalyticsEvent: Equatable, Sendable {
    case appOpened
    case tripStarted(hasLimit: Bool)
    case itemScanned(priceSource: PriceSource, symbology: Symbology?)
    /// `underLimit` is `nil` for trips without a limit.
    case tripFinished(items: Int, underLimit: Bool?)
    case insightsViewed

    var name: String {
        switch self {
        case .appOpened: "app_opened"
        case .tripStarted: "trip_started"
        case .itemScanned: "item_scanned"
        case .tripFinished: "trip_finished"
        case .insightsViewed: "insights_viewed"
        }
    }

    var properties: [String: String] {
        switch self {
        case .appOpened, .insightsViewed:
            [:]
        case .tripStarted(let hasLimit):
            ["has_limit": String(hasLimit)]
        case .itemScanned(let source, let symbology):
            ["price_source": source.rawValue, "symbology": symbology?.rawValue ?? "none"]
        case .tripFinished(let items, let underLimit):
            ["items": String(items)].merging(underLimit.map { ["under_limit": String($0)] } ?? [:]) { a, _ in a }
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
