import Network
import Observation

/// Watches the network path (`ARCHITECTURE.md` → Offline). Offline is normal in a supermarket;
/// when the path comes back, queued work (Open Food Facts now, sync in P4) is flushed.
@Observable
final class ConnectivityMonitor {
    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var handlers: [() -> Void] = []
    @ObservationIgnored private var isStarted = false

    /// Safe to call more than once (a window's `.task` can run again).
    func start() {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.update(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "scanit.connectivity"))
    }

    /// Runs every time the phone goes from offline to online.
    func onReconnect(_ handler: @escaping () -> Void) {
        handlers.append(handler)
    }

    private func update(online: Bool) {
        let cameBack = online && !isOnline
        isOnline = online
        if cameBack { handlers.forEach { $0() } }
    }
}
