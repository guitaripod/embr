import Foundation

/// What Twitch's token endpoint returns for the client credentials and refresh grants.
public struct OAuthToken: Decodable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int
    public let scope: [String]
    public let tokenType: String

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresIn: Int,
        scope: [String] = [],
        tokenType: String = "bearer"
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
        self.scope = scope
        self.tokenType = tokenType
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case tokenType = "token_type"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresIn = try container.decode(Int.self, forKey: .expiresIn)
        scope = try container.decodeIfPresent([String].self, forKey: .scope) ?? []
        tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType) ?? "bearer"
    }

    static func from(_ response: HTTPResponse) throws -> OAuthToken {
        guard response.isSuccess else {
            throw APIError.from(status: response.status, rateLimitReset: response.rateLimit?.resetAt)
        }
        return try TwitchJSON.decode(OAuthToken.self, from: response.body)
    }
}

/// The app access token grant. A tool that reads public channel data or moderates on behalf of a channel it does not
/// own asks for one of these; there is no user behind it, so endpoints that need a signed-in viewer reject it.
public enum AppAccessToken {
    public static let endpoint = URL(string: "https://id.twitch.tv/oauth2/token")!

    /// A client id and secret, never a user. Scopes are only needed by app tokens that Twitch's delegated authorization
    /// already granted to the app.
    public static func request(clientID: String, clientSecret: String, scopes: [String] = []) -> HTTPRequest {
        var fields = [
            ("client_id", clientID),
            ("client_secret", clientSecret),
            ("grant_type", "client_credentials"),
        ]
        if !scopes.isEmpty {
            fields.append(("scope", scopes.joined(separator: " ")))
        }
        return OAuthForm.post(endpoint, fields: fields)
    }

    public static func decode(_ response: HTTPResponse) throws -> OAuthToken {
        try OAuthToken.from(response)
    }
}

/// The refresh grant for an expiring user token. Twitch's public clients (the device code flow has no secret) refresh
/// with the client id alone; a confidential client passes its secret too.
public enum TokenRefresh {
    public static let endpoint = URL(string: "https://id.twitch.tv/oauth2/token")!

    public static func request(clientID: String, clientSecret: String? = nil, refreshToken: String) -> HTTPRequest {
        var fields = [
            ("client_id", clientID),
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
        ]
        if let clientSecret {
            fields.insert(("client_secret", clientSecret), at: 1)
        }
        return OAuthForm.post(endpoint, fields: fields)
    }

    public static func decode(_ response: HTTPResponse) throws -> OAuthToken {
        try OAuthToken.from(response)
    }
}
