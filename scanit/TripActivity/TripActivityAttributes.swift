import ActivityKit

/// The trip shown on the Lock Screen and in the Dynamic Island (BACKLOG LIVE-001). Compiled into
/// the app, which starts and updates it, and into the widget extension, which draws it. The app
/// sends finished text, so the extension needs no money or limit logic of its own.
nonisolated struct TripActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// "€42,80"
        var total: String
        /// "€17,20 left of €60,00" or "€3,40 over €60,00". `nil` without a limit.
        var limitText: String?
        /// 0…1 of the limit used. `nil` without a limit.
        var progress: Double?
        var level: Level
        /// Units in the cart.
        var items: Int
    }

    /// The same three states as the limit bar in the app.
    nonisolated enum Level: String, Codable, Sendable {
        case noLimit, ok, near, over
    }

    var storeName: String?
}
