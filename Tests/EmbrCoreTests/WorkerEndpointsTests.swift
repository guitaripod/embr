import Foundation
import Testing
@testable import EmbrCore

@Suite("WorkerEndpoints")
struct WorkerEndpointsTests {
    private let endpoints = WorkerEndpoints(baseURL: URL(string: "https://worker.example.com")!)

    @Test("exchange builds a POST to /auth/exchange with a JSON body that decodes to ExchangeRequest")
    func exchangeRequest() throws {
        let request = endpoints.exchange(code: "abc123", redirectURI: "embr://callback")

        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://worker.example.com/auth/exchange")
        #expect(request.headers["Content-Type"] == "application/json")

        let body = try #require(request.body)
        let decoded = try TwitchJSON.decode(WorkerAPI.ExchangeRequest.self, from: body)
        #expect(decoded == WorkerAPI.ExchangeRequest(code: "abc123", redirectURI: "embr://callback"))
    }

    @Test("refresh builds a POST to /auth/refresh with a RefreshRequest body")
    func refreshRequest() throws {
        let request = endpoints.refresh(refreshToken: "r3fr3sh")

        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://worker.example.com/auth/refresh")
        #expect(request.headers["Content-Type"] == "application/json")

        let body = try #require(request.body)
        let decoded = try TwitchJSON.decode(WorkerAPI.RefreshRequest.self, from: body)
        #expect(decoded == WorkerAPI.RefreshRequest(refreshToken: "r3fr3sh"))
    }

    @Test("appToken builds a GET to /auth/app-token with no body")
    func appTokenRequest() {
        let request = endpoints.appToken()

        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://worker.example.com/auth/app-token")
        #expect(request.body == nil)
    }

    @Test("report builds a POST to /report with a ReportRequest body")
    func reportRequest() throws {
        let request = endpoints.report(
            WorkerAPI.ReportRequest(
                channel: "somechannel",
                messageID: "m1",
                authorID: "u1",
                authorLogin: "baduser",
                reason: "Harassment",
                text: "bad text"
            )
        )

        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://worker.example.com/report")
        #expect(request.headers["Content-Type"] == "application/json")

        let body = try #require(request.body)
        let decoded = try TwitchJSON.decode(WorkerAPI.ReportRequest.self, from: body)
        #expect(decoded.reason == "Harassment")
        #expect(decoded.authorLogin == "baduser")
    }

    @Test("loginURL builds a GET with redirectURI and state query items")
    func loginURLRequest() {
        let request = endpoints.loginURL(redirectURI: "embr://callback", state: "xyz")

        #expect(request.method == .get)
        let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        #expect(components?.path == "/auth/login-url")
        let items = components?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "redirectURI", value: "embr://callback")))
        #expect(items.contains(URLQueryItem(name: "state", value: "xyz")))
    }

    @Test("playbackLive builds the right GET path")
    func playbackLivePath() {
        let request = endpoints.playbackLive(login: "shroud")

        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://worker.example.com/playback/shroud")
        #expect(request.body == nil)
    }

    @Test("playbackVOD builds the right GET path")
    func playbackVODPath() {
        let request = endpoints.playbackVOD(id: "123456789")

        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://worker.example.com/playback/vod/123456789")
    }

    @Test("playbackClip builds the right GET path")
    func playbackClipPath() {
        let request = endpoints.playbackClip(slug: "CoolClip-slug_123")

        #expect(request.method == .get)
        #expect(request.url.absoluteString == "https://worker.example.com/playback/clip/CoolClip-slug_123")
        #expect(request.body == nil)
    }

    @Test("decodePlayback tolerates the clip response's extra qualities key")
    func decodeClipPlayback() throws {
        let json = """
        { "url": "https://production.assets.clips.twitchcdn.net/abc-1080.mp4?sig=s&token=t", "qualities": [{ "quality": "1080", "frameRate": 60, "url": "https://production.assets.clips.twitchcdn.net/abc-1080.mp4?sig=s&token=t" }] }
        """
        let playback = try WorkerEndpoints.decodePlayback(Data(json.utf8))

        #expect(playback.url == "https://production.assets.clips.twitchcdn.net/abc-1080.mp4?sig=s&token=t")
        #expect(playback.expiresAt == nil)
    }

    @Test("trailing slash on base URL does not double up the path separator")
    func trailingSlashBase() {
        let trailing = WorkerEndpoints(baseURL: URL(string: "https://worker.example.com/")!)
        let request = trailing.appToken()
        #expect(request.url.absoluteString == "https://worker.example.com/auth/app-token")
    }

    @Test("decodeToken round-trips a TokenResponse JSON")
    func decodeTokenRoundTrip() throws {
        let json = """
        {
            "accessToken": "tok_abc",
            "refreshToken": "tok_refresh",
            "expiresIn": 14400,
            "scope": ["user:read:chat", "user:write:chat"],
            "userID": "44322889",
            "login": "dallas"
        }
        """
        let data = Data(json.utf8)
        let token = try WorkerEndpoints.decodeToken(data)

        #expect(token.accessToken == "tok_abc")
        #expect(token.refreshToken == "tok_refresh")
        #expect(token.expiresIn == 14400)
        #expect(token.scope == ["user:read:chat", "user:write:chat"])
        #expect(token.userID == "44322889")
        #expect(token.login == "dallas")
    }

    @Test("decodeToken tolerates an absent refreshToken and optionals")
    func decodeTokenMinimal() throws {
        let json = """
        { "accessToken": "app_token_only", "expiresIn": 5000 }
        """
        let token = try WorkerEndpoints.decodeToken(Data(json.utf8))

        #expect(token.accessToken == "app_token_only")
        #expect(token.refreshToken == nil)
        #expect(token.expiresIn == 5000)
        #expect(token.scope == nil)
        #expect(token.userID == nil)
        #expect(token.login == nil)
    }

    @Test("decodePlayback round-trips a PlaybackResponse JSON")
    func decodePlaybackRoundTrip() throws {
        let json = """
        { "url": "https://worker.example.com/hls/master.m3u8", "expiresAt": 1718000000.5 }
        """
        let playback = try WorkerEndpoints.decodePlayback(Data(json.utf8))

        #expect(playback.url == "https://worker.example.com/hls/master.m3u8")
        #expect(playback.expiresAt == 1718000000.5)
    }
}
