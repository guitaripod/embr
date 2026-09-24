import UIKit
import Combine
import EmbrCore

/// Polls the Worker's `/events/:login` endpoint while a channel is open and
/// publishes the latest active poll / prediction. Best-effort: failures emit
/// nothing rather than surfacing an error.
///
/// Most of the time a channel has no poll or prediction running, so the poller checks
/// slowly until one appears and quickly while one is live, keeping tallies fresh without
/// paying the fast rate for every minute of every stream. It stops entirely while the app
/// is in the background, where nothing it fetches could be seen.
@MainActor
final class ChannelEventsPoller {
    let events = CurrentValueSubject<ChannelEvents, Never>(.empty)

    private let login: String
    private let transport: HTTPTransport
    private let endpoints: WorkerEndpoints
    private let activeInterval: UInt64
    private let idleInterval: UInt64
    private var task: Task<Void, Never>?
    private var wanted = false
    private var lifecycle = Set<AnyCancellable>()

    init(
        login: String,
        transport: HTTPTransport = URLSessionTransport.shared,
        endpoints: WorkerEndpoints = WorkerEndpoints(baseURL: Configuration.current.workerBaseURL),
        activeIntervalSeconds: Double = 5,
        idleIntervalSeconds: Double = 15
    ) {
        self.login = login
        self.transport = transport
        self.endpoints = endpoints
        self.activeInterval = UInt64(activeIntervalSeconds * 1_000_000_000)
        self.idleInterval = UInt64(idleIntervalSeconds * 1_000_000_000)
        observeLifecycle()
    }

    func start() {
        wanted = true
        resume()
    }

    func stop() {
        wanted = false
        pause()
    }

    private func observeLifecycle() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.pause() }
            }
            .store(in: &lifecycle)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            }
            .store(in: &lifecycle)
    }

    private func resume() {
        guard wanted, task == nil, UIApplication.shared.applicationState != .background else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: self?.nextDelay ?? 15_000_000_000)
            }
        }
    }

    private func pause() {
        task?.cancel()
        task = nil
    }

    private var nextDelay: UInt64 {
        events.value == .empty ? idleInterval : activeInterval
    }

    private func poll() async {
        guard let response = try? await transport.send(endpoints.channelEvents(login: login)),
              response.isSuccess,
              let decoded = try? WorkerEndpoints.decodeChannelEvents(response.body) else { return }
        events.send(decoded)
    }

    deinit { task?.cancel() }
}
