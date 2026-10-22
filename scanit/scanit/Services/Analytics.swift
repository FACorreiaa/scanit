import OSLog
import ScanItCore
import SwiftUI

/// Product events (`ARCHITECTURE.md` → Analytics). Never carries amounts or product names.
enum AnalyticsEvent: Equatable, Sendable {
    case appOpened
    case tripStarted(hasLimit: Bool)
    case itemScanned(priceSource: PriceSource, symbology: Symbology?)
    /// One per scanned item on a device that reads labels. `ms` runs from barcode lock to Add.
    case priceOCRResult(outcome: PriceOCROutcome, ms: Int)
    /// A price that came from the label was changed later, e.g. in History.
    case priceOCRCorrected
    /// `underLimit` is `nil` for trips without a limit.
    case tripFinished(items: Int, underLimit: Bool?)
    case insightsViewed

    var name: String {
        switch self {
        case .appOpened: "app_opened"
        case .tripStarted: "trip_started"
        case .itemScanned: "item_scanned"
        case .priceOCRResult: "price_ocr_result"
        case .priceOCRCorrected: "price_ocr_corrected"
        case .tripFinished: "trip_finished"
        case .insightsViewed: "insights_viewed"
        }
    }

    var properties: [String: String] {
        switch self {
        case .appOpened, .insightsViewed, .priceOCRCorrected:
            [:]
        case .tripStarted(let hasLimit):
            ["has_limit": String(hasLimit)]
        case .itemScanned(let source, let symbology):
            ["price_source": source.rawValue, "symbology": symbology?.rawValue ?? "none"]
        case .priceOCRResult(let outcome, let ms):
            ["outcome": outcome.rawValue, "ms": String(ms)]
        case .tripFinished(let items, let underLimit):
            ["items": String(items)].merging(underLimit.map { ["under_limit": String($0)] } ?? [:]) { a, _ in a }
        }
    }
}

protocol AnalyticsClient: Sendable {
    func track(_ event: AnalyticsEvent)
}

/// Logs events locally. Replaced by a PostHog-backed client once ScanItNow has its own PostHog
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
