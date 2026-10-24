import Testing
import Foundation
@testable import EmbrCore

private actor EventLog {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

private struct RecordingTransport: HTTPTransport {
    let status: Int
    let log: EventLog
    let capture: RequestCapture

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        await log.record("send")
        await capture.set(request)
        return HTTPResponse(status: status, headers: [:], body: Data())
    }
}

private struct FailingTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        throw APIError.timeout
    }
}

private actor RequestCapture {
    private(set) var request: HTTPRequest?

    func set(_ request: HTTPRequest) {
        self.request = request
    }
}

private struct MockStore: TokenStoring {
    let log: EventLog

    func load() async -> StoredCredentials? { nil }
    func save(_ credentials: StoredCredentials) async {}
    func clear() async { await log.record("clearStore") }
}

private struct MockRevoker: TokenRevoking {
    let log: EventLog
    let failure: APIError?

    func revoke(accessToken: String) async throws {
        await log.record("revoke:\(accessToken)")
        if let failure { throw failure }
    }
}

private struct MockEraser: LocalDataErasing {
    let name: String
    let log: EventLog

    func eraseAll() async { await log.record("erase:\(name)") }
}

@Suite struct TwitchTokenRevokerTests {
    private func revoker(status: Int) -> (TwitchTokenRevoker, RequestCapture) {
        let capture = RequestCapture()
        let transport = RecordingTransport(status: status, log: EventLog(), capture: capture)
        return (TwitchTokenRevoker(transport: transport, clientID: "client id"), capture)
    }

    @Test func postsFormEncodedClientIDAndToken() async throws {
        let (revoker, capture) = revoker(status: 200)
        try await revoker.revoke(accessToken: "tok+en&x=1")
        let request = try #require(await capture.request)
        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://id.twitch.tv/oauth2/revoke")
        #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded")
        let body = String(decoding: try #require(request.body), as: UTF8.self)
        #expect(body == "client_id=client%20id&token=tok%2Ben%26x%3D1")
    }

    @Test func alreadyInvalidTokenCountsAsRevoked() async throws {
        let (revoker, _) = revoker(status: 400)
        try await revoker.revoke(accessToken: "dead")
    }

    @Test func serverErrorIsThrown() async {
        let (revoker, _) = revoker(status: 503)
        await #expect(throws: APIError.self) {
            try await revoker.revoke(accessToken: "tok")
        }
    }

    @Test func transportFailureIsThrown() async {
        let revoker = TwitchTokenRevoker(transport: FailingTransport(), clientID: "id")
        await #expect(throws: APIError.timeout) {
            try await revoker.revoke(accessToken: "tok")
        }
    }
}

@Suite struct AccountDeletionCoordinatorTests {
    private func coordinator(log: EventLog, failure: APIError? = nil) -> AccountDeletionCoordinator {
        AccountDeletionCoordinator(
            store: MockStore(log: log),
            revoker: MockRevoker(log: log, failure: failure),
            erasers: [MockEraser(name: "database", log: log), MockEraser(name: "caches", log: log)]
        )
    }

    @Test func revokesThenClearsKeychainThenErasesLocalData() async throws {
        let log = EventLog()
        try await coordinator(log: log).deleteAccount(accessToken: "abc")
        #expect(await log.events == ["revoke:abc", "clearStore", "erase:database", "erase:caches"])
    }

    @Test func revokeFailureLeavesEverythingUntouched() async {
        let log = EventLog()
        await #expect(throws: APIError.timeout) {
            try await coordinator(log: log, failure: .timeout).deleteAccount(accessToken: "abc")
        }
        #expect(await log.events == ["revoke:abc"])
    }

    @Test func withoutATokenItSkipsTheRevokeButStillErases() async throws {
        let log = EventLog()
        try await coordinator(log: log).deleteAccount(accessToken: nil)
        #expect(await log.events == ["clearStore", "erase:database", "erase:caches"])
    }

    @Test func retryAfterFailureCompletes() async throws {
        let log = EventLog()
        _ = try? await coordinator(log: log, failure: .timeout).deleteAccount(accessToken: "abc")
        try await coordinator(log: log).deleteAccount(accessToken: "abc")
        #expect(await log.events == ["revoke:abc", "revoke:abc", "clearStore", "erase:database", "erase:caches"])
    }
}
