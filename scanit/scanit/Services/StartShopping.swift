import AppIntents
import Observation

/// Requests that arrive from outside the app's own screens: Siri, Shortcuts, the Action Button
/// (BACKLOG ADD-004). The intent only raises the request; the Trip tab acts on it, so the free-trip
/// quota and the start sheet stay in one place.
@Observable
final class ShortcutActions {
    static let shared = ShortcutActions()

    /// Set while a "start shopping" request is waiting for the Trip tab.
    private(set) var startShopping: UUID?

    func requestStartShopping() {
        startShopping = UUID()
    }

    /// `true` once per request, for the screen that is going to act on it.
    func takeStartShopping() -> Bool {
        guard startShopping != nil else { return false }
        startShopping = nil
        return true
    }
}

/// Opens the app ready to shop: the scanner when a trip is in progress, otherwise the start
/// sheet with the last store already chosen.
nonisolated struct StartShoppingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start shopping"
    static let description = IntentDescription("Opens ScanItNow ready to scan: the scanner if a trip is in progress, or a new trip.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutActions.shared.requestStartShopping()
        return .result()
    }
}

nonisolated struct ScanItShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartShoppingIntent(),
            phrases: [
                "Start shopping with \(.applicationName)",
                "Start a \(.applicationName) trip",
            ],
            shortTitle: "Start shopping",
            systemImageName: "barcode.viewfinder"
        )
    }
}
