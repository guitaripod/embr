import Foundation

/// One user in a channel's chatters, moderators or VIP list. Twitch returns the same three fields for all three.
public struct ChannelUser: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public let userID: String
    public let userLogin: String
    public let userName: String

    public var id: String { userID }

    public init(userID: String, userLogin: String, userName: String) {
        self.userID = userID
        self.userLogin = userLogin
        self.userName = userName
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case userLogin = "user_login"
        case userName = "user_name"
    }
}

/// A user in a channel's ban list. `expiresAt` is nil for a permanent ban, where Twitch sends an empty string instead
/// of a timestamp.
public struct BannedUser: Decodable, Sendable, Equatable, Identifiable {
    public let userID: String
    public let userLogin: String
    public let userName: String
    public let createdAt: Date
    public let expiresAt: Date?
    public let reason: String?
    public let moderatorID: String
    public let moderatorLogin: String
    public let moderatorName: String

    public var id: String { userID }

    public var isPermanent: Bool { expiresAt == nil }

    public init(
        userID: String,
        userLogin: String,
        userName: String,
        createdAt: Date,
        expiresAt: Date? = nil,
        reason: String? = nil,
        moderatorID: String,
        moderatorLogin: String,
        moderatorName: String
    ) {
        self.userID = userID
        self.userLogin = userLogin
        self.userName = userName
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.reason = reason
        self.moderatorID = moderatorID
        self.moderatorLogin = moderatorLogin
        self.moderatorName = moderatorName
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case userLogin = "user_login"
        case userName = "user_name"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case reason
        case moderatorID = "moderator_id"
        case moderatorLogin = "moderator_login"
        case moderatorName = "moderator_name"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(String.self, forKey: .userID)
        userLogin = try container.decode(String.self, forKey: .userLogin)
        userName = try container.decode(String.self, forKey: .userName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        expiresAt = Self.date(from: try container.decodeIfPresent(String.self, forKey: .expiresAt))
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        moderatorID = try container.decode(String.self, forKey: .moderatorID)
        moderatorLogin = try container.decode(String.self, forKey: .moderatorLogin)
        moderatorName = try container.decode(String.self, forKey: .moderatorName)
    }

    private static func date(from raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return TwitchJSON.date(from: raw)
    }
}
