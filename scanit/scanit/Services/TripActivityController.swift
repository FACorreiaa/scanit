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
final class TripActivityController {
    private var activity: Activity<TripActivityAttributes>?
    private var shown: TripActivityAttributes.ContentState?

    init() {
        // After a relaunch mid-trip the activity is still on the Lock Screen: take it back.
        activity = Activity<TripActivityAttributes>.activities.first
    }

    /// Call after every change. `nil` means no trip in progress.
    func sync(_ session: ShoppingSession?) {
        guard let session else {
            end()
            return
        }
        let state = TripActivityAttributes.ContentState(session: session)
        if let activity {
            guard state != shown else { return }
            shown = state
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            // Off in Settings, or not available: the trip works the same without it.
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            shown = state
            activity = try? Activity.request(
                attributes: TripActivityAttributes(storeName: session.store?.name),
                content: ActivityContent(state: state, staleDate: nil)
            )
        }
    }

    private func end() {
        shown = nil
        activity = nil
        // Every one of them, in case an earlier launch left one behind.
        for running in Activity<TripActivityAttributes>.activities {
            Task { await running.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
