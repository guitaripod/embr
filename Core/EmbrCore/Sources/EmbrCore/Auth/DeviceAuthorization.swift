import Foundation

/// Twitch's Device Code Grant Flow, the sign-in of a screen without a browser: the TV asks Twitch for a code, the
/// person approves it at twitch.tv/activate on their phone, and the TV polls until Twitch hands over the tokens. The
/// requests carry the client id and no secret; refreshing the tokens later goes through the worker like every other
/// Embr session.
public enum DeviceAuthorization {
    /// What a TV session needs: the follows for the Following shelves and chat to read. Sending stays on the phone.
    public static let scopes = ["user:read:follows", "chat:read"]

    public static let deviceURL = URL(string: "https://id.twitch.tv/oauth2/device")!
    public static let tokenURL = URL(string: "https://id.twitch.tv/oauth2/token")!
    public static let grantType = "urn:ietf:params:oauth:grant-type:device_code"

    /// Twitch's answer to the first request: the code to show and the one to poll with.
    public struct Start: Sendable, Equatable, Decodable {
        public let deviceCode: String
        public let userCode: String
        /// The activation page with the code already filled in, which is what the QR code on screen opens.
        public let verificationURI: URL
        public let expiresIn: Int
        public let interval: Int

        public init(deviceCode: String, userCode: String, verificationURI: URL, expiresIn: Int, interval: Int) {
            self.deviceCode = deviceCode
            self.userCode = userCode
            self.verificationURI = verificationURI
            self.expiresIn = expiresIn
            self.interval = interval
        }

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationURI = "verification_uri"
            case expiresIn = "expires_in"
            case interval
        }

        /// The time between two polls, never below Twitch's floor of one second.
        public var pollInterval: TimeInterval {
            TimeInterval(max(1, interval))
        }
    }

    public struct Token: Sendable, Equatable, Decodable {
        public let accessToken: String
        public let refreshToken: String?
        public let expiresIn: Int
        public let scope: [String]?

        public init(accessToken: String, refreshToken: String?, expiresIn: Int, scope: [String]?) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresIn = expiresIn
            self.scope = scope
        }

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case scope
        }
    }

    /// One answer to a poll.
    public enum PollResult: Sendable, Equatable {
        case authorized(Token)
        /// Not approved yet; poll again after the interval.
        case pending
        /// Polling too fast; add five seconds to the interval, as the OAuth device flow asks.
        case slowDown
        /// The code is spent or timed out; start over with a new one.
        case expired
        /// The person declined on the activation page.
        case denied
        case failed(String)
    }

    public static func startRequest(clientID: String, scopes: [String] = scopes) -> HTTPRequest {
        formPost(deviceURL, fields: [("client_id", clientID), ("scopes", scopes.joined(separator: " "))])
    }

    public static func tokenRequest(clientID: String, deviceCode: String, scopes: [String] = scopes) -> HTTPRequest {
        formPost(tokenURL, fields: [
            ("client_id", clientID),
            ("scopes", scopes.joined(separator: " ")),
            ("device_code", deviceCode),
            ("grant_type", grantType),
        ])
    }

    public static func decodeStart(_ response: HTTPResponse) throws -> Start {
        guard response.isSuccess else {
            throw APIError.from(status: response.status, rateLimitReset: response.rateLimit?.resetAt)
        }
        return try TwitchJSON.decode(Start.self, from: response.body)
    }

    public static func pollResult(_ response: HTTPResponse) -> PollResult {
        if response.isSuccess {
            do {
                return .authorized(try TwitchJSON.decode(Token.self, from: response.body))
            } catch {
                return .failed(String(describing: error))
            }
        }
        let message = errorMessage(in: response.body)
        switch message {
        case let text where text.contains("authorization_pending"):
            return .pending
        case let text where text.contains("slow_down"):
            return .slowDown
        case let text where text.contains("expired") || text.contains("invalid device code"):
            return .expired
        case let text where text.contains("denied"):
            return .denied
        default:
            return response.status == 429 ? .slowDown : .failed(message.isEmpty ? "status \(response.status)" : message)
        }
    }

    /// The user code split in two halves, the way people read a code off a TV: `ABCD-EFGH`.
    public static func displayCode(_ userCode: String) -> String {
        let code = userCode.uppercased()
        guard code.count == 8 else { return code }
        return "\(code.prefix(4))-\(code.suffix(4))"
    }

    private static func errorMessage(in body: Data) -> String {
        struct ErrorBody: Decodable {
            let message: String?
            let error: String?
        }
        guard let decoded = try? JSONDecoder().decode(ErrorBody.self, from: body) else {
            return String(decoding: body, as: UTF8.self).lowercased()
        }
        return [decoded.message, decoded.error].compactMap { $0 }.joined(separator: " ").lowercased()
    }

    private static func formPost(_ url: URL, fields: [(String, String)]) -> HTTPRequest {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        let encoded = (components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        return HTTPRequest(
            method: .post,
            url: url,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: Data(encoded.utf8)
        )
    }
}
