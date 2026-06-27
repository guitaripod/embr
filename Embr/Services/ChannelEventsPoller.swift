import Foundation
import Combine
import EmbrCore

/// Polls the Worker's `/events/:login` endpoint while a channel is open and
/// publishes the latest active poll / prediction. Best-effort: failures emit
/// nothing rather than surfacing an error.
@MainActor
final class ChannelEventsPoller {
    let events = CurrentValueSubject<ChannelEvents, Never>(.empty)

    private let login: String
    private let transport: HTTPTransport
    private let endpoints: WorkerEndpoints
    private let interval: UInt64
    private var task: Task<Void, Never>?

    init(
        login: String,
        transport: HTTPTransport = URLSessionTransport.shared,
        endpoints: WorkerEndpoints = WorkerEndpoints(baseURL: Configuration.current.workerBaseURL),
        intervalSeconds: Double = 5
    ) {
        self.login = login
        self.transport = transport
        self.endpoints = endpoints
        self.interval = UInt64(intervalSeconds * 1_000_000_000)
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: self?.interval ?? 5_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func poll() async {
        guard let response = try? await transport.send(endpoints.channelEvents(login: login)),
              response.isSuccess,
              let decoded = try? WorkerEndpoints.decodeChannelEvents(response.body) else { return }
        events.send(decoded)
    }

    deinit { task?.cancel() }
}
