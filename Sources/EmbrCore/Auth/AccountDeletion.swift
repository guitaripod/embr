import Foundation

public protocol TokenRevoking: Sendable {
    func revoke(accessToken: String) async throws
}

public protocol LocalDataErasing: Sendable {
    func eraseAll() async
}

/// Revokes a user access token at Twitch (`POST id.twitch.tv/oauth2/revoke`). The device holds
/// the tokens and the worker keeps none, so the revoke goes straight to Twitch with the app's
/// public client id.
public struct TwitchTokenRevoker: TokenRevoking {
    public static let endpoint = URL(string: "https://id.twitch.tv/oauth2/revoke")!

    private let transport: HTTPTransport
    private let clientID: String

    public init(transport: HTTPTransport, clientID: String) {
        self.transport = transport
        self.clientID = clientID
    }

    /// A 400 means Twitch already considers the token invalid, which is the state revoking
    /// aims for. Any other non-success status, or a transport failure, is thrown so the
    /// caller does not erase the only copy of a token that is still live.
    public func revoke(accessToken: String) async throws {
        let response = try await transport.send(Self.request(clientID: clientID, token: accessToken))
        guard response.isSuccess || response.status == 400 else {
            throw APIError.from(status: response.status, rateLimitReset: response.rateLimit?.resetAt)
        }
    }

    public static func request(clientID: String, token: String) -> HTTPRequest {
        var request = HTTPRequest(method: .post, url: endpoint)
        request.setHeader("Content-Type", "application/x-www-form-urlencoded")
        request.body = "client_id=\(formEncoded(clientID))&token=\(formEncoded(token))".data(using: .utf8)
        return request
    }

    private static func formEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// Deletes the user's Embr account: revokes the Twitch token, removes the stored credentials,
/// then erases every on-device record. The revoke runs first and its failure aborts the whole
/// operation, so a failed network call never leaves a live token with no copy on the device.
public struct AccountDeletionCoordinator: Sendable {
    private let store: TokenStoring
    private let revoker: TokenRevoking
    private let erasers: [any LocalDataErasing]

    public init(store: TokenStoring, revoker: TokenRevoking, erasers: [any LocalDataErasing]) {
        self.store = store
        self.revoker = revoker
        self.erasers = erasers
    }

    public func deleteAccount(accessToken: String?) async throws {
        if let accessToken {
            try await revoker.revoke(accessToken: accessToken)
        }
        await store.clear()
        for eraser in erasers {
            await eraser.eraseAll()
        }
    }
}
