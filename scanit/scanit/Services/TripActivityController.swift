import ActivityKit
import ScanItCore

extension TripActivityAttributes.ContentState {
    /// What the Lock Screen says for a trip, in the same words as the trip screen.
    init(session: ShoppingSession) {
        let status = session.limitStatus
        var limitText: String?
        if let limit = session.limit, let remaining = status.remainingMinor {
            let amount = Money(amountMinor: abs(remaining), currency: session.currency).formatted()
            limitText = remaining < 0 ? "\(amount) over \(limit.formatted())" : "\(amount) left of \(limit.formatted())"
        }
        self.init(
            total: session.total.formatted(),
            limitText: limitText,
            progress: status.progress.map { min(max($0, 0), 1) },
            level: TripActivityAttributes.Level(status.state),
            items: session.itemCount
        )
    }
}

extension TripActivityAttributes.Level {
    init(_ state: LimitState) {
        switch state {
        case .noLimit: self = .noLimit
        case .ok: self = .ok
        case .near: self = .near
        case .over: self = .over
        }
    }
}

/// Keeps one Live Activity in step with the active trip (BACKLOG LIVE-001). Everything is local:
/// the app updates it on every change to the cart, and there is no push server.
///
/// Only the activity's id is kept. `Activity` is not `Sendable`, so each update looks it up again
/// inside a nonisolated task instead of carrying it off the main actor (Swift 6 rejects that).
final class TripActivityController {
    private var activityID: String?
    private var shown: TripActivityAttributes.ContentState?

    init() {
        // After a relaunch mid-trip the activity is still on the Lock Screen: take it back.
        activityID = Activity<TripActivityAttributes>.activities.first?.id
    }

    /// Call after every change. `nil` means no trip in progress.
    func sync(_ session: ShoppingSession?) {
        guard let session else {
            end()
            return
        }
        let state = TripActivityAttributes.ContentState(session: session)
        if let activityID {
            guard state != shown else { return }
            shown = state
            Task { await Self.update(id: activityID, to: state) }
        } else {
            // Off in Settings, or not available: the trip works the same without it.
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            shown = state
            activityID = (try? Activity.request(
                attributes: TripActivityAttributes(storeName: session.store?.name),
                content: ActivityContent(state: state, staleDate: nil)
            ))?.id
        }
    }

    private func end() {
        shown = nil
        activityID = nil
        Task { await Self.endAll() }
    }

    private nonisolated static func update(id: String, to state: TripActivityAttributes.ContentState) async {
        guard let activity = Activity<TripActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    /// Every one of them, in case an earlier launch left one behind.
    private nonisolated static func endAll() async {
        for activity in Activity<TripActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
