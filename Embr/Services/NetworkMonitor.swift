import Foundation
import Combine
import Network

/// App-wide connectivity awareness. Publishes a one-shot signal each time the
/// network transitions from offline → online, so subsystems can proactively
/// reconnect instead of waiting for a slow timeout or a 30s watchdog.
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true

    /// Emits when connectivity is restored after having been lost.
    let restored = PassthroughSubject<Void, Never>()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "network.monitor")
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.update(online: online) }
        }
        monitor.start(queue: queue)
    }

    private func update(online: Bool) {
        guard online != isOnline else { return }
        let wasOffline = !isOnline
        isOnline = online
        AppLogger.shared.info("network \(online ? "online" : "offline")", category: .app)
        if online && wasOffline {
            restored.send(())
        }
    }
}
