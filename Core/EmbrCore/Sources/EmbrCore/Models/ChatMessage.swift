import Foundation

public struct ChatMessage: Sendable, Equatable, Identifiable {
    public let id: String
    public let channelID: String
    public let timestamp: Date
    public let author: ChatUser
    public let fragments: [ChatFragment]
    public let badges: [MessageBadge]
    public let messageType: MessageType
    public let isAction: Bool
    public let bits: Int?
    public let reply: ReplyContext?
    public let notice: ChannelNotice?
    public let sharedChatSource: SharedChatSource?
    public var moderation: ModerationState

    public init(
        id: String,
        channelID: String,
        timestamp: Date,
        author: ChatUser,
        fragments: [ChatFragment],
        badges: [MessageBadge] = [],
        messageType: MessageType = .regular,
        isAction: Bool = false,
        bits: Int? = nil,
        reply: ReplyContext? = nil,
        notice: ChannelNotice? = nil,
        sharedChatSource: SharedChatSource? = nil,
        moderation: ModerationState = .visible
    ) {
        self.id = id
        self.channelID = channelID
        self.timestamp = timestamp
        self.author = author
        self.fragments = fragments
        self.badges = badges
        self.messageType = messageType
        self.isAction = isAction
        self.bits = bits
        self.reply = reply
        self.notice = notice
        self.sharedChatSource = sharedChatSource
        self.moderation = moderation
    }

    public var plainText: String {
        fragments.map(\.text).joined()
    }
}

public struct ChatUser: Sendable, Equatable, Hashable {
    public let id: String
    public let login: String
    public let displayName: String
    public let color: ChatColor?

    public init(id: String, login: String, displayName: String, color: ChatColor? = nil) {
        self.id = id
        self.login = login
        self.displayName = displayName
        self.color = color
    }
}

public enum ChatFragment: Sendable, Equatable {
    case text(String)
    case emote(TwitchEmoteRef)
    case cheermote(CheermoteRef)
    case mention(MentionRef)

    public var text: String {
        switch self {
        case .text(let value): return value
        case .emote(let emote): return emote.text
        case .cheermote(let cheer): return cheer.text
        case .mention(let mention): return "@\(mention.displayName)"
        }
    }
}

public struct TwitchEmoteRef: Sendable, Equatable, Hashable {
    public let id: String
    public let text: String
    public let setID: String?
    public let ownerID: String?
    public let formats: [EmoteFormat]

    public init(id: String, text: String, setID: String? = nil, ownerID: String? = nil, formats: [EmoteFormat] = [.static]) {
        self.id = id
        self.text = text
        self.setID = setID
        self.ownerID = ownerID
        self.formats = formats
    }
}

public struct CheermoteRef: Sendable, Equatable, Hashable {
    public let prefix: String
    public let bits: Int
    public let tier: Int
    public let text: String

    public init(prefix: String, bits: Int, tier: Int, text: String) {
        self.prefix = prefix
        self.bits = bits
        self.tier = tier
        self.text = text
    }
}

public struct MentionRef: Sendable, Equatable, Hashable {
    public let userID: String
    public let login: String
    public let displayName: String

    public init(userID: String, login: String, displayName: String) {
        self.userID = userID
        self.login = login
        self.displayName = displayName
    }
}

public struct MessageBadge: Sendable, Equatable, Hashable {
    public let setID: String
    public let id: String
    public let info: String?

    public init(setID: String, id: String, info: String? = nil) {
        self.setID = setID
        self.id = id
        self.info = info
    }
}

public enum MessageType: String, Sendable, Equatable, Codable {
    case regular
    case channelPointsHighlighted
    case channelPointsSubOnly
    case userIntro
    case powerUpsMessageEffect
    case powerUpsGigantifiedEmote
}

public struct ReplyContext: Sendable, Equatable, Hashable {
    public let parentMessageID: String
    public let parentUserID: String
    public let parentLogin: String
    public let parentDisplayName: String
    public let parentText: String
    public let threadParentMessageID: String?

    public init(parentMessageID: String, parentUserID: String, parentLogin: String, parentDisplayName: String, parentText: String, threadParentMessageID: String? = nil) {
        self.parentMessageID = parentMessageID
        self.parentUserID = parentUserID
        self.parentLogin = parentLogin
        self.parentDisplayName = parentDisplayName
        self.parentText = parentText
        self.threadParentMessageID = threadParentMessageID
    }
}

public struct SharedChatSource: Sendable, Equatable, Hashable {
    public let broadcasterID: String
    public let broadcasterLogin: String
    public let broadcasterName: String
    public let isSourceOnly: Bool

    public init(broadcasterID: String, broadcasterLogin: String, broadcasterName: String, isSourceOnly: Bool) {
        self.broadcasterID = broadcasterID
        self.broadcasterLogin = broadcasterLogin
        self.broadcasterName = broadcasterName
        self.isSourceOnly = isSourceOnly
    }
}

public enum ModerationState: Sendable, Equatable, Hashable {
    case visible
    case deleted
    case timedOut
    case banned
}

public struct ChannelNotice: Sendable, Equatable {
    public let kind: NoticeKind
    public let systemMessage: String

    public init(kind: NoticeKind, systemMessage: String) {
        self.kind = kind
        self.systemMessage = systemMessage
    }
}

public enum NoticeKind: String, Sendable, Equatable, Codable {
    case sub
    case resub
    case subGift
    case communitySubGift
    case giftPaidUpgrade
    case primePaidUpgrade
    case raid
    case unraid
    case payItForward
    case announcement
    case bitsBadgeTier
    case charityDonation
    case other
}

public struct ChatColor: Sendable, Equatable, Hashable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        var value = hex
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let int = UInt32(value, radix: 16) else { return nil }
        self.red = UInt8((int >> 16) & 0xFF)
        self.green = UInt8((int >> 8) & 0xFF)
        self.blue = UInt8(int & 0xFF)
    }

    public var hexString: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }
}
