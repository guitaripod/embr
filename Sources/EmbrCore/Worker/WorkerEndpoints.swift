import Foundation

public struct WorkerEndpoints: Sendable {
    public let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    public func loginURL(redirectURI: String, state: String) -> HTTPRequest {
        let url = QueryEncoder.url(
            path("/auth/login-url"),
            items: [("redirectURI", redirectURI), ("state", state)]
        ) ?? baseURL.appendingPathComponent("auth/login-url")
        return HTTPRequest(method: .get, url: url)
    }

    public func exchange(code: String, redirectURI: String) -> HTTPRequest {
        jsonPost("/auth/exchange", body: WorkerAPI.ExchangeRequest(code: code, redirectURI: redirectURI))
    }

    public func refresh(refreshToken: String) -> HTTPRequest {
        jsonPost("/auth/refresh", body: WorkerAPI.RefreshRequest(refreshToken: refreshToken))
    }

    public func appToken() -> HTTPRequest {
        HTTPRequest(method: .get, url: url(for: "/auth/app-token"))
    }

    public func report(_ body: WorkerAPI.ReportRequest) -> HTTPRequest {
        jsonPost("/report", body: body)
    }

    public func playbackLive(login: String) -> HTTPRequest {
        HTTPRequest(method: .get, url: url(for: "/playback/\(escape(login))"))
    }

    public func playbackVOD(id: String) -> HTTPRequest {
        HTTPRequest(method: .get, url: url(for: "/playback/vod/\(escape(id))"))
    }

    public func channelEvents(login: String) -> HTTPRequest {
        HTTPRequest(method: .get, url: url(for: "/events/\(escape(login))"))
    }

    public static func decodeChannelEvents(_ data: Data) throws -> ChannelEvents {
        try TwitchJSON.decode(ChannelEvents.self, from: data)
    }

    public static func decodeToken(_ data: Data) throws -> WorkerAPI.TokenResponse {
        try TwitchJSON.decode(WorkerAPI.TokenResponse.self, from: data)
    }

    public static func decodePlayback(_ data: Data) throws -> WorkerAPI.PlaybackResponse {
        try TwitchJSON.decode(WorkerAPI.PlaybackResponse.self, from: data)
    }

    private func jsonPost(_ relativePath: String, body: some Encodable) -> HTTPRequest {
        let data = try? TwitchJSON.encoder.encode(body)
        return HTTPRequest(
            method: .post,
            url: url(for: relativePath),
            headers: ["Content-Type": "application/json"],
            body: data
        )
    }

    private func url(for relativePath: String) -> URL {
        URL(string: path(relativePath)) ?? baseURL.appendingPathComponent(String(relativePath.drop(while: { $0 == "/" })))
    }

    private func path(_ relativePath: String) -> String {
        let trimmed = baseURL.absoluteString.hasSuffix("/")
            ? String(baseURL.absoluteString.dropLast())
            : baseURL.absoluteString
        return trimmed + relativePath
    }

    private func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
    }
}
