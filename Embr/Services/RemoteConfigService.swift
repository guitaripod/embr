import UIKit
import Combine
import EmbrCore

/// Reads the Worker's `/config` switches at launch and on every return to the foreground, and
/// remembers the last answer so a cold start offline still honours it. Playback asks this
/// synchronously, so it never waits on the network before a stream can start.
@MainActor
final class RemoteConfigService {
    static let shared = RemoteConfigService()

    private(set) var current: WorkerAPI.AppConfig

    private let transport: HTTPTransport
    private let endpoints: WorkerEndpoints
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var fetching = false
    private var lastFetchAt: Date?
    private static let cacheKey = "remoteConfig.v1"
    private static let minimumFetchInterval: TimeInterval = 300

    init(
        transport: HTTPTransport = URLSessionTransport.shared,
        endpoints: WorkerEndpoints = WorkerEndpoints(baseURL: Configuration.current.workerBaseURL),
        defaults: UserDefaults = .standard
    ) {
        self.transport = transport
        self.endpoints = endpoints
        self.defaults = defaults
        current = defaults.data(forKey: Self.cacheKey)
            .flatMap { try? WorkerEndpoints.decodeAppConfig($0) } ?? .standard
    }

    var startsLiveInEmbed: Bool { current.livePlayback == .embed }

    func start() {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            .store(in: &cancellables)
        refresh()
    }

    private func refresh() {
        guard !fetching else { return }
        if let last = lastFetchAt, Date().timeIntervalSince(last) < Self.minimumFetchInterval { return }
        fetching = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.fetching = false }
            guard let response = try? await self.transport.send(self.endpoints.appConfig()),
                  response.isSuccess,
                  let config = try? WorkerEndpoints.decodeAppConfig(response.body) else { return }
            self.lastFetchAt = Date()
            if config != self.current {
                AppLogger.shared.info("remote config: live playback -> \(config.livePlayback.rawValue)", category: .playback)
            }
            self.current = config
            self.defaults.set(response.body, forKey: Self.cacheKey)
        }
    }
}
