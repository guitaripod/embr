import Foundation

struct ChatMessageEvent: Decodable, Sendable {
    let broadcasterUserID: String
    let chatterUserID: String
    let chatterUserLogin: String
    let chatterUserName: String
    let messageID: String
    let color: String?
    let message: ChatMessageBody
    let badges: [ChatBadgePayload]
    let messageType: String
    let cheer: ChatCheerPayload?
    let reply: ChatReplyPayload?
    let channelPointsCustomRewardID: String?
    let sourceBroadcasterUserID: String?
    let sourceBroadcasterUserLogin: String?
    let sourceBroadcasterUserName: String?
    let sourceMessageID: String?
    let isSourceOnly: Bool?

    enum CodingKeys: String, CodingKey {
        case broadcasterUserID = "broadcaster_user_id"
        case chatterUserID = "chatter_user_id"
        case chatterUserLogin = "chatter_user_login"
        case chatterUserName = "chatter_user_name"
        case messageID = "message_id"
        case color
        case message
        case badges
        case messageType = "message_type"
        case cheer
        case reply
        case channelPointsCustomRewardID = "channel_points_custom_reward_id"
        case sourceBroadcasterUserID = "source_broadcaster_user_id"
        case sourceBroadcasterUserLogin = "source_broadcaster_user_login"
        case sourceBroadcasterUserName = "source_broadcaster_user_name"
        case sourceMessageID = "source_message_id"
        case isSourceOnly = "is_source_only"
    }
}

struct ChatNotificationEvent: Decodable, Sendable {
    let broadcasterUserID: String
    let chatterUserID: String
    let chatterUserLogin: String
    let chatterUserName: String
    let messageID: String
    let color: String?
    let message: ChatMessageBody
    let badges: [ChatBadgePayload]
    let systemMessage: String
    let noticeType: String
    let sourceBroadcasterUserID: String?
    let sourceBroadcasterUserLogin: String?
    let sourceBroadcasterUserName: String?
    let sourceMessageID: String?

    enum CodingKeys: String, CodingKey {
        case broadcasterUserID = "broadcaster_user_id"
        case chatterUserID = "chatter_user_id"
        case chatterUserLogin = "chatter_user_login"
        case chatterUserName = "chatter_user_name"
        case messageID = "message_id"
        case color
        case message
        case badges
        case systemMessage = "system_message"
        case noticeType = "notice_type"
        case sourceBroadcasterUserID = "source_broadcaster_user_id"
        case sourceBroadcasterUserLogin = "source_broadcaster_user_login"
        case sourceBroadcasterUserName = "source_broadcaster_user_name"
        case sourceMessageID = "source_message_id"
    }
}

struct ChatMessageBody: Decodable, Sendable {
    let text: String
    let fragments: [ChatFragmentPayload]
}

struct ChatFragmentPayload: Decodable, Sendable {
    let type: String
    let text: String
    let cheermote: ChatCheermotePayload?
    let emote: ChatEmotePayload?
    let mention: ChatMentionPayload?
}

struct ChatCheermotePayload: Decodable, Sendable {
    let prefix: String
    let bits: Int
    let tier: Int
}

struct ChatEmotePayload: Decodable, Sendable {
    let id: String
    let emoteSetID: String?
    let ownerID: String?
    let format: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case emoteSetID = "emote_set_id"
        case ownerID = "owner_id"
        case format
    }
}

struct ChatMentionPayload: Decodable, Sendable {
    let userID: String
    let userLogin: String
    let userName: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case userLogin = "user_login"
        case userName = "user_name"
    }
}

struct ChatBadgePayload: Decodable, Sendable {
    let setID: String
    let id: String
    let info: String?

    enum CodingKeys: String, CodingKey {
        case setID = "set_id"
        case id
        case info
    }
}

struct ChatCheerPayload: Decodable, Sendable {
    let bits: Int
}

struct ChatReplyPayload: Decodable, Sendable {
    let parentMessageID: String
    let parentUserID: String
    let parentUserLogin: String
    let parentUserName: String
    let parentMessageBody: String
    let threadMessageID: String?

    enum CodingKeys: String, CodingKey {
        case parentMessageID = "parent_message_id"
        case parentUserID = "parent_user_id"
        case parentUserLogin = "parent_user_login"
        case parentUserName = "parent_user_name"
        case parentMessageBody = "parent_message_body"
        case threadMessageID = "thread_message_id"
    }
}

struct ChatMessageDeleteEvent: Decodable, Sendable {
    let broadcasterUserID: String
    let targetUserID: String?
    let messageID: String

    enum CodingKeys: String, CodingKey {
        case broadcasterUserID = "broadcaster_user_id"
        case targetUserID = "target_user_id"
        case messageID = "message_id"
    }
}

struct ChatClearEvent: Decodable, Sendable {
    let broadcasterUserID: String

    enum CodingKeys: String, CodingKey {
        case broadcasterUserID = "broadcaster_user_id"
    }
}

struct ChatClearUserMessagesEvent: Decodable, Sendable {
    let targetUserID: String
    let targetUserLogin: String
    let targetUserName: String

    enum CodingKeys: String, CodingKey {
        case targetUserID = "target_user_id"
        case targetUserLogin = "target_user_login"
        case targetUserName = "target_user_name"
    }
}
