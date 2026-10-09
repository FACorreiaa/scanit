import Foundation

/// Free-tier rules for "ScanIt Unlimited" (`ARCHITECTURE.md` → Purchases, BACKLOG REL-003).
/// Pure, so the rules are tested without StoreKit and the Android port can mirror them.
nonisolated struct PaywallPolicy: Equatable, Sendable {
    /// Off until launch, so TestFlight testers in the strangers gate (P2) are never limited.
    var isEnabled: Bool
    /// OPEN (owner): proposed 4 trips per calendar month.
    var freeTripsPerMonth: Int
    /// OPEN (owner): proposed last 10 trips visible in History.
    var visibleHistory: Int

    static let launch = PaywallPolicy(isEnabled: false, freeTripsPerMonth: 4, visibleHistory: 10)

    /// The quota is checked only when starting a trip; a trip in progress always finishes.
    func canStartTrip(tripsThisMonth: Int, isUnlimited: Bool) -> Bool {
        !isEnabled || isUnlimited || tripsThisMonth < freeTripsPerMonth
    }

    /// Newest-first trips split into what History shows and how many are hidden. Hidden trips are
    /// kept, never deleted; unlocking shows them again.
    func visibleTrips<T>(_ newestFirst: [T], isUnlimited: Bool) -> (visible: [T], hiddenCount: Int) {
        guard isEnabled, !isUnlimited, newestFirst.count > visibleHistory else { return (newestFirst, 0) }
        return (Array(newestFirst.prefix(visibleHistory)), newestFirst.count - visibleHistory)
    }

    /// Trips that use up the monthly quota: started this calendar month and not cancelled.
    static func tripsCounted(startedAt dates: [Date], now: Date, calendar: Calendar = .current) -> Int {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return 0 }
        // Half-open: `DateInterval.contains` includes the end, which is midnight on the 1st of next month.
        return dates.filter { $0 >= month.start && $0 < month.end }.count
    }
}
