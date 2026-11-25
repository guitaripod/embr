import Foundation
import Testing
import EmbrCore
@testable import EmbrCLIKit

private let streamsJSON = """
{
  "data": [
    {
      "id": "1", "user_id": "100", "user_login": "shroud", "user_name": "shroud",
      "game_id": "1", "game_name": "Escape From Tarkov", "title": "raid",
      "viewer_count": 1234, "started_at": "2026-01-02T03:04:05Z", "language": "en",
      "thumbnail_url": "https://example/{width}x{height}.jpg", "tags": [], "is_mature": false
    }
  ],
  "pagination": { "cursor": "next-cursor" }
}
"""

private let usersJSON = """
{"data":[{"id":"100","login":"shroud","display_name":"shroud","profile_image_url":"https://example/p.png","description":"","broadcaster_type":"partner","created_at":"2012-01-01T00:00:00Z"}]}
"""

private let sendJSON = """
{"data":[{"message_id":"m-1","is_sent":true,"drop_reason":null}]}
"""

private let subscriptionJSON = """
{"data":[{"id":"sub-1","status":"websocket_connected","type":"channel.chat.message","version":"1","condition":{},"transport":{},"created_at":"2026-01-02T03:04:05Z"}],"total":1,"total_cost":0,"max_total_cost":10,"pagination":{}}
"""

private func response(_ status: Int, _ json: String) -> HTTPResponse {
    HTTPResponse(status: status, headers: [:], body: Data(json.utf8))
}

private func fakeTransport() -> FakeTransport {
    FakeTransport { request in
        let path = request.url.path
        if request.url.host == "id.twitch.tv" {
            switch path {
            case "/oauth2/device":
                return response(200, #"{"device_code":"device-1","user_code":"ABCD1234","verification_uri":"https://www.twitch.tv/activate","expires_in":1800,"interval":5}"#)
            case "/oauth2/token":
                return response(200, #"{"access_token":"device-token","refresh_token":"device-refresh","expires_in":3600,"scope":["user:read:chat"]}"#)
            default:
                return response(200, #"{"client_id":"client-id","login":"tester","scopes":["user:read:chat"],"user_id":"999","expires_in":3600}"#)
            }
        }
        switch (request.method, path) {
        case (.get, "/helix/streams"):
            return response(200, streamsJSON)
        case (.get, "/helix/users"):
            let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
            let id = components?.queryItems?.first { $0.name == "id" }?.value
            let login = components?.queryItems?.first { $0.name == "login" }?.value
            let userID = id ?? "100"
            let userLogin = login ?? (id == nil ? "shroud" : "user")
            return response(200, """
            {"data":[{"id":"\(userID)","login":"\(userLogin)","display_name":"\(userLogin)","description":"","broadcaster_type":"partner","created_at":"2012-01-01T00:00:00Z"}]}
            """)
        case (.post, "/helix/chat/messages"):
            return response(200, sendJSON)
        case (.post, "/helix/moderation/bans"):
            return response(200, #"{"data":[{"user_id":"456","is_permanent":false}]}"#)
        case (.patch, "/helix/channels"):
            return response(204, "")
        case (.post, "/helix/eventsub/subscriptions"):
            return response(202, subscriptionJSON)
        case (.get, "/helix/chat/chatters"):
            return response(200, #"{"data":[{"user_id":"1","user_login":"a","user_name":"A"}],"pagination":{},"total":1}"#)
        default:
            return response(404, #"{"message":"unexpected \#(request.method.rawValue) \#(path)"}"#)
        }
    }
}

@Suite("CLI commands", .serialized)
struct CommandTests {
    @Test func streamsTopUsesTheJsonEnvelope() async throws {
        let dir = TestRun.make()
        let transport = fakeTransport()
        let result = await TestRun.run(["streams", "top", "--first", "1", "--json"], transport: transport, configDirectory: dir)
        #expect(result.code == 0)
        let data = try #require(result.out.json as? [String: Any])
        #expect(data["ok"] as? Bool == true)
        #expect(data["command"] as? String == "streams top")
        let rows = try #require(data["data"] as? [[String: Any]])
        #expect(rows.first?["userLogin"] as? String == "shroud")
        #expect((data["pagination"] as? [String: Any])?["cursor"] as? String == "next-cursor")
        #expect(transport.requests.first?.url.path == "/helix/streams")
    }

    @Test func sendResolvesTheBroadcasterAndSendsAsTheTokenUser() async throws {
        let dir = TestRun.make()
        let transport = fakeTransport()
        let result = await TestRun.run(["chat", "send", "shroud", "hello", "world", "--json"], transport: transport, configDirectory: dir)
        #expect(result.code == 0)
        let request = try #require(transport.requests.last)
        #expect(request.url.path == "/helix/chat/messages")
        let body = try #require(request.body)
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["broadcaster_id"] as? String == "100")
        #expect(payload["sender_id"] as? String == "999")
        #expect(payload["message"] as? String == "hello world")
    }

    @Test func banBuildsTheNestedBody() async throws {
        let dir = TestRun.make()
        let transport = fakeTransport()
        let result = await TestRun.run(
            ["mod", "ban", "shroud", "456", "--as", "999", "--duration", "600", "--reason", "spam", "--json"],
            transport: transport,
            configDirectory: dir
        )
        #expect(result.code == 0)
        let request = try #require(transport.requests.last)
        #expect(request.url.path == "/helix/moderation/bans")
        let body = try #require(request.body)
        let root = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let inner = try #require(root["data"] as? [String: Any])
        #expect(inner["user_id"] as? String == "456")
        #expect(inner["duration"] as? Int == 600)
        #expect(inner["reason"] as? String == "spam")
    }

    @Test func channelEditSendsOnlyTheSetFields() async throws {
        let dir = TestRun.make()
        let transport = fakeTransport()
        let result = await TestRun.run(
            ["channels", "edit", "100", "--title", "New title", "--tag", "English", "--json"],
            transport: transport,
            configDirectory: dir
        )
        #expect(result.code == 0)
        let request = try #require(transport.requests.last)
        #expect(request.method == .patch)
        let body = try #require(request.body)
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["title"] as? String == "New title")
        #expect(payload["tags"] as? [String] == ["English"])
        #expect(payload["game_id"] == nil)
    }

    @Test func eventSubCreateSendsTheSubscription() async throws {
        let dir = TestRun.make()
        let transport = fakeTransport()
        let result = await TestRun.run(
            [
                "eventsub", "create", "channel.follow",
                "--session", "session-1",
                "--condition", "broadcaster_user_id=1",
                "--condition", "moderator_user_id=2",
                "--json"
            ],
            transport: transport,
            configDirectory: dir
        )
        #expect(result.code == 0)
        let request = try #require(transport.requests.last)
        #expect(request.method == .post)
        let body = try #require(request.body)
        let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["type"] as? String == "channel.follow")
        let condition = try #require(payload["condition"] as? [String: String])
        #expect(condition["broadcaster_user_id"] == "1")
        let transportBody = try #require(payload["transport"] as? [String: String])
        #expect(transportBody["session_id"] == "session-1")
    }

    @Test func chattersDecodesTheTotal() async throws {
        let dir = TestRun.make()
        let transport = fakeTransport()
        let result = await TestRun.run(
            ["chat", "chatters", "100", "--as", "999", "--json"],
            transport: transport,
            configDirectory: dir
        )
        #expect(result.code == 0)
        let data = try #require(result.out.json as? [String: Any])
        let rows = try #require(data["data"] as? [[String: Any]])
        #expect(rows.first?["userLogin"] as? String == "a")
    }

    @Test func dryRunPrintsTheRequestAndSendsNothing() async throws {
        let dir = TestRun.make()
        let transport = fakeTransport()
        let result = await TestRun.run(
            ["mod", "ban", "100", "456", "--as", "999", "--reason", "spam", "--dry-run", "--json"],
            transport: transport,
            configDirectory: dir
        )
        #expect(result.code == 0)
        #expect(transport.requests.isEmpty)
        let data = try #require(result.out.json as? [String: Any])
        let payload = try #require(data["data"] as? [String: Any])
        #expect(payload["method"] as? String == "POST")
        #expect((payload["url"] as? String)?.contains("/helix/moderation/bans") == true)
        let headers = try #require(payload["headers"] as? [String: String])
        #expect(headers["Authorization"] == "REDACTED")
    }

    @Test func authStatusValidatesTheEnvironmentToken() async throws {
        let dir = TestRun.make()
        let transport = fakeTransport()
        let result = await TestRun.run(["auth", "status", "--json"], transport: transport, configDirectory: dir)
        #expect(result.code == 0)
        let data = try #require(result.out.json as? [String: Any])
        let payload = try #require(data["data"] as? [String: Any])
        #expect(payload["authenticated"] as? Bool == true)
        #expect(payload["login"] as? String == "tester")
        #expect((payload["scopes"] as? [String])?.contains("user:read:chat") == true)
    }

    @Test func loginNoWaitPrintsTheDeviceCode() async throws {
        let dir = TestRun.make()
        let transport = fakeTransport()
        let result = await TestRun.run(["auth", "login", "--no-wait", "--json"], transport: transport, configDirectory: dir)
        #expect(result.code == 0)
        let data = try #require(result.out.json as? [String: Any])
        let payload = try #require(data["data"] as? [String: Any])
        #expect(payload["userCode"] as? String == "ABCD1234")
        #expect(payload["deviceCode"] as? String == "device-1")
        #expect(payload["verificationURI"] as? String == "https://www.twitch.tv/activate")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("credentials.json").path) == false)
    }

    @Test func pollStoresTheAuthorizedToken() async throws {
        let dir = TestRun.make()
        let transport = fakeTransport()
        let result = await TestRun.run(["auth", "poll", "--device-code", "device-1", "--json"], transport: transport, configDirectory: dir)
        #expect(result.code == 0)
        let data = try #require(result.out.json as? [String: Any])
        let payload = try #require(data["data"] as? [String: Any])
        #expect(payload["status"] as? String == "authorized")
        #expect(payload["login"] as? String == "tester")
        let store = CredentialsStore(environment: ["EMBR_CONFIG_DIR": dir.path])
        #expect(store.profile("default")?.accessToken == "device-token")
        #expect(store.profile("default")?.refreshToken == "device-refresh")
    }

    @Test func dryRunRedactsSecretsInBodies() async throws {
        let dir = TestRun.make()
        let transport = fakeTransport()
        let result = await TestRun.run(
            ["auth", "app-token", "--dry-run", "--json"],
            transport: transport,
            configDirectory: dir,
            extraEnvironment: ["EMBR_CLIENT_SECRET": "s3cr3t-value"]
        )
        #expect(result.code == 0)
        #expect(!result.out.text.contains("s3cr3t-value"))
        let data = try #require(result.out.json as? [String: Any])
        let payload = try #require(data["data"] as? [String: Any])
        let body = try #require(payload["body"] as? String)
        #expect(body.contains("client_secret=REDACTED"))
    }

    @Test func errorsUseTheErrorEnvelopeAndExitCode() async throws {
        let dir = TestRun.make()
        let transport = FakeTransport { _ in response(401, #"{"message":"invalid token"}"#) }
        let result = await TestRun.run(["streams", "top", "--json"], transport: transport, configDirectory: dir)
        #expect(result.code == 3)
        let data = try #require(result.err.json as? [String: Any])
        let error = try #require(data["error"] as? [String: Any])
        #expect(error["kind"] as? String == "auth")
        #expect(result.out.text.isEmpty)
    }
}
