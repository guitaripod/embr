import Foundation
import Combine
import EmbrCore

enum StreamStatus: Sendable, Equatable {
    case live(LiveStream)
    case offline
}

/// Polls `streams(userIDs:)` on a jittered interval while a channel is open and
/// publishes whether the broadcaster is currently live (with the fresh stream
/// snapshot) or has gone offline. Best-effort: transient failures emit nothing.
@MainActor
final class LiveStatsPoller {
    let status = PassthroughSubject<StreamStatus, Never>()

    private let userID: String
    private let api: TwitchAPIProviding
    private let baseInterval: Double
    private var task: Task<Void, Never>?

    init(userID: String, api: TwitchAPIProviding = AppContainer.shared.api, intervalSeconds: Double = 60) {
        self.userID = userID
        self.api = api
        self.baseInterval = intervalSeconds
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                let delay = self?.nextDelay() ?? 60_000_000_000
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { break }
                await self?.poll()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func nextDelay() -> UInt64 {
        let jitter = Double.random(in: -0.15...0.15) * baseInterval
        return UInt64(max(1, baseInterval + jitter) * 1_000_000_000)
    }

    private func poll() async {
        guard let streams = try? await api.streams(userIDs: [userID]) else { return }
        status.send(streams.first.map(StreamStatus.live) ?? .offline)
    }

    deinit { task?.cancel() }
}
