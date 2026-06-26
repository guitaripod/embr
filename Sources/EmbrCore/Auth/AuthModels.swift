import Foundation

public struct StoredCredentials: Sendable, Equatable, Codable {
    public let userID: String
    public let login: String
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date
    public let scopes: [String]

    public init(userID: String, login: String, accessToken: String, refreshToken: String?, expiresAt: Date, scopes: [String]) {
        self.userID = userID
        self.login = login
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
    }

    public func isExpiring(within interval: TimeInterval, now: Date) -> Bool {
        expiresAt.timeIntervalSince(now) < interval
    }
}

public struct AuthenticatedUser: Sendable, Equatable {
    public let id: String
    public let login: String
    public let displayName: String
    public let scopes: [String]

    public init(id: String, login: String, displayName: String, scopes: [String]) {
        self.id = id
        self.login = login
        self.displayName = displayName
        self.scopes = scopes
    }
}

public struct TokenValidation: Sendable, Equatable, Codable {
    public let clientID: String
    public let login: String?
    public let userID: String?
    public let scopes: [String]
    public let expiresIn: Int

    public init(clientID: String, login: String?, userID: String?, scopes: [String], expiresIn: Int) {
        self.clientID = clientID
        self.login = login
        self.userID = userID
        self.scopes = scopes
        self.expiresIn = expiresIn
    }

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case login
        case userID = "user_id"
        case scopes
        case expiresIn = "expires_in"
    }
}

public enum WorkerAPI {
    public struct ExchangeRequest: Codable, Sendable, Equatable {
        public let code: String
        public let redirectURI: String
        public init(code: String, redirectURI: String) {
            self.code = code
            self.redirectURI = redirectURI
        }
    }

    public struct RefreshRequest: Codable, Sendable, Equatable {
        public let refreshToken: String
        public init(refreshToken: String) {
            self.refreshToken = refreshToken
        }
    }

    public struct TokenResponse: Codable, Sendable, Equatable {
        public let accessToken: String
        public let refreshToken: String?
        public let expiresIn: Int
        public let scope: [String]?
        public let userID: String?
        public let login: String?
        public init(accessToken: String, refreshToken: String?, expiresIn: Int, scope: [String]?, userID: String?, login: String?) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresIn = expiresIn
            self.scope = scope
            self.userID = userID
            self.login = login
        }
    }

    public struct ReportRequest: Codable, Sendable, Equatable {
        public let channel: String?
        public let messageID: String?
        public let authorID: String?
        public let authorLogin: String?
        public let reason: String
        public let text: String?
        public init(
            channel: String?,
            messageID: String?,
            authorID: String?,
            authorLogin: String?,
            reason: String,
            text: String?
        ) {
            self.channel = channel
            self.messageID = messageID
            self.authorID = authorID
            self.authorLogin = authorLogin
            self.reason = reason
            self.text = text
        }
    }

    public struct ErrorResponse: Codable, Sendable, Equatable {
        public let error: String
        public init(error: String) {
            self.error = error
        }
    }
}

public enum TwitchScopes {
    public static let readChat = "user:read:chat"
    public static let writeChat = "user:write:chat"
    public static let readFollows = "user:read:follows"
    public static let readBlocked = "user:read:blocked_users"
    public static let manageBlocked = "user:manage:blocked_users"
    public static let manageChatColor = "user:manage:chat_color"
    public static let manageWhispers = "user:manage:whispers"
    public static let moderatorManageBannedUsers = "moderator:manage:banned_users"
    public static let moderatorManageChatMessages = "moderator:manage:chat_messages"
    public static let moderatorManageChatSettings = "moderator:manage:chat_settings"
    public static let moderatorManageAnnouncements = "moderator:manage:announcements"

    public static let viewerDefault: [String] = [
        readChat, writeChat, readFollows, manageChatColor
    ]
}
