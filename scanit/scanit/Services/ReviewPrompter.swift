import Foundation
import Observation

/// Decides when to ask for an App Store rating. iOS still decides whether the sheet shows; this
/// only keeps the ask to good moments, and rare.
///
/// A success is a finished trip that was kept, counted at most once per calendar day, so the ask
/// comes after trips on three different days. It never comes in the first 24 hours or more than
/// once in 120 days. A milestone (the first kept trip) asks at once, even on day 1; only the
/// cooldown and `isEnabled` hold it back. Asking resets the count.
///
/// Logic only, kept per device in `defaults` under `scanit.review.*`, with the clock injected so
/// the rules are testable without waiting days. `TripView` makes the request.
@Observable @MainActor final class ReviewPrompter {
    static let successThreshold = 3
    static let firstSessionGrace: TimeInterval = 24 * 60 * 60
    static let cooldown: TimeInterval = 120 * 24 * 60 * 60
    /// Long enough for the summary sheet's dismissal to settle first.
    static let settleDelay: Duration = .seconds(1.5)

    private enum Key {
        static let enabled = "scanit.review.enabled"
        static let firstSeenAt = "scanit.review.firstSeenAt"
        static let successCount = "scanit.review.successCount"
        static let lastCountedDay = "scanit.review.lastCountedDay"
        static let lastPromptAt = "scanit.review.lastPromptAt"
        static func milestone(_ key: String) -> String { "scanit.review.milestone.\(key)" }
    }

    /// Set by a success or milestone that earns the ask; the trip screen observes it.
    private(set) var isPromptDue = false

    /// On by default. There is no Settings screen yet, so nothing turns it off in the app.
    /// Off clears any pending ask.
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Key.enabled)
            if !isEnabled { isPromptDue = false }
        }
    }

    /// UI tests (`-ui-testing`): never raise an ask. Debug builds always show the review sheet,
    /// which would cover the XCUITest flows.
    private let isSuppressed: Bool
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        isSuppressed: Bool = false
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.isSuppressed = isSuppressed
        self.isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        if defaults.object(forKey: Key.firstSeenAt) == nil { defaults.set(now(), forKey: Key.firstSeenAt) }
    }

    var successCount: Int { defaults.integer(forKey: Key.successCount) }

    /// A trip was finished and kept. Counts once per calendar day.
    func recordSuccess() {
        let today = calendar.startOfDay(for: now())
        let lastCounted = defaults.object(forKey: Key.lastCountedDay) as? Date
        if lastCounted.map({ !calendar.isDate($0, inSameDayAs: today) }) ?? true {
            defaults.set(today, forKey: Key.lastCountedDay)
            defaults.set(successCount + 1, forKey: Key.successCount)
        }
        if successCount >= Self.successThreshold, isPastFirstSession, canAsk { isPromptDue = true }
    }

    /// A first-time or celebratory moment: asks without waiting for the count or the first day.
    /// The cooldown and `isEnabled` still apply. With `once`, it fires at most one time per
    /// install; the key is spent the first time the moment happens, whether or not it asked.
    func recordMilestone(once key: String? = nil) {
        if let key {
            guard !defaults.bool(forKey: Key.milestone(key)) else { return }
            defaults.set(true, forKey: Key.milestone(key))
        }
        if canAsk { isPromptDue = true }
    }

    /// Call once the request has been handed to iOS.
    func didPrompt() {
        defaults.set(0, forKey: Key.successCount)
        defaults.set(now(), forKey: Key.lastPromptAt)
        isPromptDue = false
    }

    /// The moment passed (screen left, app backgrounded). The count is kept, so the next
    /// success asks instead.
    func skipPrompt() {
        isPromptDue = false
    }

    private var isPastFirstSession: Bool {
        let firstSeen = defaults.object(forKey: Key.firstSeenAt) as? Date ?? now()
        return now().timeIntervalSince(firstSeen) >= Self.firstSessionGrace
    }

    /// Switched on, not under UI tests, and past the cooldown since the last ask.
    private var canAsk: Bool {
        guard isEnabled, !isSuppressed else { return false }
        guard let last = defaults.object(forKey: Key.lastPromptAt) as? Date else { return true }
        return now().timeIntervalSince(last) >= Self.cooldown
    }
}
