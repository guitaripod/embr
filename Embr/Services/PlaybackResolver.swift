import Foundation
import EmbrCore

actor PlaybackResolver: PlaybackResolving {
    static let shared = PlaybackResolver()

    private let transport: HTTPTransport
    private let endpoints: WorkerEndpoints

    init(
        transport: HTTPTransport = URLSessionTransport.shared,
        endpoints: WorkerEndpoints = WorkerEndpoints(baseURL: Configuration.current.workerBaseURL)
    ) {
        self.transport = transport
        self.endpoints = endpoints
    }

    func resolveLive(channelLogin: String) async throws -> PlaybackResolution {
        try await resolve(request: endpoints.playbackLive(login: channelLogin), label: channelLogin)
    }

    func resolveVOD(videoID: String) async throws -> PlaybackResolution {
        try await resolve(request: endpoints.playbackVOD(id: videoID), label: videoID)
    }

    private func resolve(request: HTTPRequest, label: String) async throws -> PlaybackResolution {
        let response = try await transport.send(request)
        guard response.isSuccess else {
            AppLogger.shared.warn("Playback resolve failed for \(label): status \(response.status)", category: .playback)
            throw APIError.from(status: response.status, rateLimitReset: response.rateLimit?.resetAt)
        }
        let decoded = try WorkerEndpoints.decodePlayback(response.body)
        guard let url = URL(string: decoded.url) else {
            throw APIError.decoding("Invalid playback URL: \(decoded.url)")
        }
        AppLogger.shared.info("Resolved playback for \(label)", category: .playback)
        return PlaybackResolution(
            masterPlaylistURL: url,
            qualities: [],
            expiresAt: decoded.expiresAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}
