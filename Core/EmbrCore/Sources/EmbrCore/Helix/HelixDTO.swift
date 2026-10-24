import Foundation

public struct HelixResponse<T: Decodable & Sendable>: Decodable, Sendable {
    public let data: [T]
    public let pagination: Pagination?

    public struct Pagination: Decodable, Sendable {
        public let cursor: String?
    }
}

struct StreamDTO: Decodable, Sendable {
    let id: String
    let userID: String
    let userLogin: String
    let userName: String
    let gameID: String
    let gameName: String
    let title: String
    let viewerCount: Int
    let startedAt: Date
    let language: String
    let thumbnailURL: String
    let tags: [String]?
    let isMature: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case userLogin = "user_login"
        case userName = "user_name"
        case gameID = "game_id"
        case gameName = "game_name"
        case title
        case viewerCount = "viewer_count"
        case startedAt = "started_at"
        case language
        case thumbnailURL = "thumbnail_url"
        case tags
        case isMature = "is_mature"
    }
}

struct GameDTO: Decodable, Sendable {
    let id: String
    let name: String
    let boxArtURL: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case boxArtURL = "box_art_url"
    }
}

struct ChannelSearchDTO: Decodable, Sendable {
    let id: String
    let broadcasterLogin: String
    let displayName: String
    let gameID: String
    let gameName: String
    let title: String
    let isLive: Bool
    let tags: [String]?
    let thumbnailURL: String

    enum CodingKeys: String, CodingKey {
        case id
        case broadcasterLogin = "broadcaster_login"
        case displayName = "display_name"
        case gameID = "game_id"
        case gameName = "game_name"
        case title
        case isLive = "is_live"
        case tags
        case thumbnailURL = "thumbnail_url"
    }
}

struct UserDTO: Decodable, Sendable {
    let id: String
    let login: String
    let displayName: String
    let profileImageURL: String?
    let description: String?
    let broadcasterType: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case displayName = "display_name"
        case profileImageURL = "profile_image_url"
        case description
        case broadcasterType = "broadcaster_type"
        case createdAt = "created_at"
    }
}

struct ChannelDTO: Decodable, Sendable {
    let broadcasterID: String
    let broadcasterLogin: String
    let broadcasterName: String
    let gameID: String
    let gameName: String
    let title: String
    let broadcasterLanguage: String
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case broadcasterID = "broadcaster_id"
        case broadcasterLogin = "broadcaster_login"
        case broadcasterName = "broadcaster_name"
        case gameID = "game_id"
        case gameName = "game_name"
        case title
        case broadcasterLanguage = "broadcaster_language"
        case tags
    }
}

struct VideoDTO: Decodable, Sendable {
    let id: String
    let userID: String
    let userLogin: String
    let userName: String
    let title: String
    let createdAt: Date
    let publishedAt: Date
    let thumbnailURL: String
    let viewCount: Int
    let duration: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case userLogin = "user_login"
        case userName = "user_name"
        case title
        case createdAt = "created_at"
        case publishedAt = "published_at"
        case thumbnailURL = "thumbnail_url"
        case viewCount = "view_count"
        case duration
        case type
    }
}

struct ClipDTO: Decodable, Sendable {
    let id: String
    let broadcasterID: String
    let broadcasterName: String
    let creatorName: String
    let title: String
    let viewCount: Int
    let createdAt: Date
    let thumbnailURL: String?
    let duration: Double
    let url: String?

    enum CodingKeys: String, CodingKey {
        case id
        case broadcasterID = "broadcaster_id"
        case broadcasterName = "broadcaster_name"
        case creatorName = "creator_name"
        case title
        case viewCount = "view_count"
        case createdAt = "created_at"
        case thumbnailURL = "thumbnail_url"
        case duration
        case url
    }
}

struct FollowedChannelDTO: Decodable, Sendable {
    let broadcasterID: String
    let broadcasterLogin: String
    let broadcasterName: String
    let followedAt: Date

    enum CodingKeys: String, CodingKey {
        case broadcasterID = "broadcaster_id"
        case broadcasterLogin = "broadcaster_login"
        case broadcasterName = "broadcaster_name"
        case followedAt = "followed_at"
    }
}

struct EmoteImagesDTO: Decodable, Sendable {
    let url1x: String?
    let url2x: String?
    let url4x: String?

    enum CodingKeys: String, CodingKey {
        case url1x = "url_1x"
        case url2x = "url_2x"
        case url4x = "url_4x"
    }
}

struct EmoteDTO: Decodable, Sendable {
    let id: String
    let name: String
    let images: EmoteImagesDTO
    let format: [String]?
    let scale: [String]?
    let themeMode: [String]?
    let emoteType: String?
    let emoteSetID: String?
    let ownerID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case images
        case format
        case scale
        case themeMode = "theme_mode"
        case emoteType = "emote_type"
        case emoteSetID = "emote_set_id"
        case ownerID = "owner_id"
    }
}

struct BadgeVersionDTO: Decodable, Sendable {
    let id: String
    let imageURL1x: String?
    let imageURL2x: String?
    let imageURL4x: String?
    let title: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id
        case imageURL1x = "image_url_1x"
        case imageURL2x = "image_url_2x"
        case imageURL4x = "image_url_4x"
        case title
        case description
    }
}

struct BadgeSetDTO: Decodable, Sendable {
    let setID: String
    let versions: [BadgeVersionDTO]

    enum CodingKeys: String, CodingKey {
        case setID = "set_id"
        case versions
    }
}

struct ChatSettingsDTO: Decodable, Sendable {
    let emoteMode: Bool
    let followerMode: Bool
    let followerModeDuration: Int?
    let slowMode: Bool
    let slowModeWaitTime: Int?
    let subscriberMode: Bool
    let uniqueChatMode: Bool

    enum CodingKeys: String, CodingKey {
        case emoteMode = "emote_mode"
        case followerMode = "follower_mode"
        case followerModeDuration = "follower_mode_duration"
        case slowMode = "slow_mode"
        case slowModeWaitTime = "slow_mode_wait_time"
        case subscriberMode = "subscriber_mode"
        case uniqueChatMode = "unique_chat_mode"
    }
}

struct DropReasonDTO: Decodable, Sendable {
    let code: String
    let message: String
}

struct SendMessageResultDTO: Decodable, Sendable {
    let messageID: String?
    let isSent: Bool
    let dropReason: DropReasonDTO?

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case isSent = "is_sent"
        case dropReason = "drop_reason"
    }
}
