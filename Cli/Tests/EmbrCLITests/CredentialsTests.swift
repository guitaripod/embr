import Foundation
import Testing
import EmbrCore
@testable import EmbrCLIKit

@Suite("Credentials", .serialized)
struct CredentialsTests {
    @Test func storeWritesA0600File() throws {
        let directory = TestRun.make()
        let store = CredentialsStore(url: directory.appendingPathComponent("credentials.json"))
        try store.update("default") { file in
            file.profiles["default"] = StoredProfile(clientID: "cid", accessToken: "tok", scopes: ["chat:read"])
        }
        #expect(store.exists)
        #expect(store.permissions() == 0o600)
        let loaded = store.load()
        #expect(loaded.profiles["default"]?.clientID == "cid")
        #expect(loaded.profiles["default"]?.accessToken == "tok")
    }

    @Test func environmentTokenWinsOverTheConfigFile() async throws {
        let directory = TestRun.make()
        let store = CredentialsStore(url: directory.appendingPathComponent("credentials.json"))
        try store.update("default") { file in
            file.profiles["default"] = StoredProfile(clientID: "file-client", accessToken: "file-token")
        }
        let transport = FakeTransport { _ in
            HTTPResponse(status: 200, headers: [:], body: Data(#"{"client_id":"env-client","login":"x","scopes":[],"user_id":"1","expires_in":3600}"#.utf8))
        }
        let client = APIClient(transport: transport)
        let service = AuthService(
            store: store,
            environment: ["EMBR_CLIENT_ID": "env-client", "EMBR_ACCESS_TOKEN": "env-token"],
            client: client,
            profile: "default"
        )
        let auth = try await service.current()
        #expect(auth.accessToken == "env-token")
        #expect(auth.clientID == "env-client")
        #expect(auth.source == .environment)
    }

    @Test func expiredConfigTokenRefreshesAndPersists() async throws {
        let directory = TestRun.make()
        let store = CredentialsStore(url: directory.appendingPathComponent("credentials.json"))
        try store.update("default") { file in
            file.profiles["default"] = StoredProfile(
                clientID: "cid",
                accessToken: "old",
                refreshToken: "refresh-1",
                scopes: ["chat:read"],
                expiresAt: Date().addingTimeInterval(-60)
            )
        }
        let transport = FakeTransport { request in
            if request.url.path == "/oauth2/token" {
                return HTTPResponse(
                    status: 200,
                    headers: [:],
                    body: Data(#"{"access_token":"new","refresh_token":"refresh-2","expires_in":3600,"scope":["chat:read"]}"#.utf8)
                )
            }
            return HTTPResponse(status: 404, headers: [:], body: Data())
        }
        let client = APIClient(transport: transport)
        let service = AuthService(
            store: store,
            environment: [:],
            client: client,
            profile: "default"
        )
        let auth = try await service.current()
        #expect(auth.accessToken == "new")
        #expect(auth.refreshToken == "refresh-2")
        #expect(transport.requests.first?.url.path == "/oauth2/token")
        let stored = store.profile("default")
        #expect(stored?.accessToken == "new")
        #expect(stored?.refreshToken == "refresh-2")
    }

    @Test func missingClientIDIsAnAuthError() async {
        let directory = TestRun.make()
        let store = CredentialsStore(url: directory.appendingPathComponent("credentials.json"))
        let client = APIClient(transport: FakeTransport { _ in HTTPResponse(status: 500, headers: [:], body: Data()) })
        let service = AuthService(store: store, environment: [:], client: client, profile: "default")
        do {
            _ = try await service.current()
            Issue.record("expected an error")
        } catch let error as CLIError {
            #expect(error.kind == .auth)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}
