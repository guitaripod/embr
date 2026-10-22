import EmbrCore
import Foundation
import MidgarCore
import Testing

@testable import Embr

struct MidgarGatewayTransportTests {
    private let endpoints = WorkerEndpoints(baseURL: Configuration.current.workerBaseURL)

    private static let report = WorkerAPI.ReportRequest(
        channel: "somechannel", messageID: "m1", authorID: nil, authorLogin: nil, reason: "spam", text: nil
    )

    @Test func configurationPointsTheWorkerAtTheGatewayRoute() {
        let configuration = Configuration.current
        #expect(configuration.workerBaseURL.absoluteString == "https://api.midgarcorp.cc/v1/embr")
        #expect(configuration.twitchRedirectURI == "https://api.midgarcorp.cc/v1/embr/auth/callback")
    }

    @Test func workerRequestsGoToTheEmbrRouteWithTheAppID() async throws {
        let seen = LockedBox<URLRequest?>(nil)
        let client = GatewayStub.client { request in
            seen.value = request
            return (200, ["Content-Type": "application/json"], Data(#"{"url":"https://api.midgarcorp.cc/v1/embr/hls/proxy?src=x"}"#.utf8))
        }
        let transport = MidgarGatewayTransport(client: client)

        let response = try await transport.send(endpoints.playbackLive(login: "some_channel"))

        #expect(response.status == 200)
        let request = try #require(seen.value)
        #expect(request.url?.absoluteString == "https://api.midgarcorp.cc/v1/embr/playback/some_channel")
        #expect(request.value(forHTTPHeaderField: "X-App-ID") == "embr")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.httpMethod == "GET")
    }

    @Test func queryItemsSurvive() async throws {
        let seen = LockedBox<URLRequest?>(nil)
        let transport = MidgarGatewayTransport(client: GatewayStub.client { request in
            seen.value = request
            return (200, [:], Data(#"{"url":"https://x"}"#.utf8))
        })

        _ = try await transport.send(endpoints.loginURL(redirectURI: "https://api.midgarcorp.cc/v1/embr/auth/callback", state: "s 1"))

        let components = try #require(seen.value?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(components.path == "/v1/embr/auth/login-url")
        #expect(components.queryItems?.first { $0.name == "state" }?.value == "s 1")
        #expect(components.queryItems?.first { $0.name == "redirectURI" }?.value == "https://api.midgarcorp.cc/v1/embr/auth/callback")
    }

    @Test func aJSONBodyReachesTheWorkerIntact() async throws {
        let seen = LockedBox<URLRequest?>(nil)
        let transport = MidgarGatewayTransport(client: GatewayStub.client { request in
            seen.value = request
            return (200, [:], Data(#"{"accessToken":"a","expiresIn":3600}"#.utf8))
        })

        _ = try await transport.send(endpoints.exchange(code: "the-code", redirectURI: "https://api.midgarcorp.cc/v1/embr/auth/callback"))

        let request = try #require(seen.value)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/embr/auth/exchange")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(object == ["code": "the-code", "redirectURI": "https://api.midgarcorp.cc/v1/embr/auth/callback"])
    }

    @Test func statusesTheServiceAnswersWithComeBackAsResponses() async throws {
        let cases: [(Int, [String: String])] = [(401, [:]), (404, [:]), (429, ["Retry-After": "30"]), (500, [:])]
        for (status, headers) in cases {
            let transport = MidgarGatewayTransport(client: GatewayStub.client { _ in
                (status, headers, Data(#"{"error":{"code":"x","message":"y"}}"#.utf8))
            })
            let response = try await transport.send(endpoints.report(Self.report))
            #expect(response.status == status)
            #expect(!response.isSuccess)
        }
    }

    @Test func aRateLimitCarriesItsResetTime() async throws {
        let transport = MidgarGatewayTransport(client: GatewayStub.client { _ in (429, ["Retry-After": "30"], Data("{}".utf8)) })
        let response = try await transport.send(endpoints.report(Self.report))
        let reset = try #require(response.rateLimit?.resetAt)
        #expect(abs(reset.timeIntervalSinceNow - 30) < 5)
    }

    @Test func noConnectionThrowsAnAPIError() async {
        let transport = MidgarGatewayTransport(client: GatewayStub.client { _ in throw URLError(.notConnectedToInternet) })
        await #expect(throws: APIError.self) {
            _ = try await transport.send(endpoints.report(Self.report))
        }
    }

    @Test func aURLOutsideTheRouteIsRefused() async {
        let transport = MidgarGatewayTransport(client: GatewayStub.client { _ in (200, [:], Data("{}".utf8)) })
        let outside = HTTPRequest(url: URL(string: "https://api.twitch.tv/helix/users")!)
        await #expect(throws: APIError.self) { _ = try await transport.send(outside) }
        let sibling = HTTPRequest(url: URL(string: "https://api.midgarcorp.cc/v1/embrx/config")!)
        await #expect(throws: APIError.self) { _ = try await transport.send(sibling) }
    }

    @Test func fragmentsRoundTrip() throws {
        let json = #"{"a":[1,2.5,null,true,"s"],"b":{"c":"d"}}"#
        let fragment = try JSONDecoder().decode(JSONFragment.self, from: Data(json.utf8))
        let again = try JSONDecoder().decode(JSONFragment.self, from: JSONEncoder().encode(fragment))
        #expect(fragment == again)
        #expect(fragment == .object(["a": .array([.number(1), .number(2.5), .null, .bool(true), .string("s")]), "b": .object(["c": .string("d")])]))
    }
}

final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}
