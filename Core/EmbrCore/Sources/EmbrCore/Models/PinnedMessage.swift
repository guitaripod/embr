import Foundation

/// The message a channel currently has pinned, with the fragments chat already understands. Twitch leaves `message`
/// null when it can no longer resolve the content, which arrives here as an empty text and no fragments.
public struct PinnedMessage: Decodable, Sendable, Equatable, Identifiable {
    public let messageID: String
    public let broadcasterID: String
    public let senderUserID: String
    public let senderUserLogin: String
    public let senderUserName: String
    public let pinnedByUserID: String
    public let pinnedByUserLogin: String
    public let pinnedByUserName: String
    public let text: String?
    public let fragments: [ChatFragment]
    public let startsAt: Date
    public let endsAt: Date?
    public let updatedAt: Date

    public var id: String { messageID }

    public var isPinnedUntilStreamEnds: Bool { endsAt == nil }

    public init(
        messageID: String,
        broadcasterID: String,
        senderUserID: String,
        senderUserLogin: String,
        senderUserName: String,
        pinnedByUserID: String,
        pinnedByUserLogin: String,
        pinnedByUserName: String,
        text: String? = nil,
        fragments: [ChatFragment] = [],
        startsAt: Date,
        endsAt: Date? = nil,
        updatedAt: Date
    ) {
        self.messageID = messageID
        self.broadcasterID = broadcasterID
        self.senderUserID = senderUserID
        self.senderUserLogin = senderUserLogin
        self.senderUserName = senderUserName
        self.pinnedByUserID = pinnedByUserID
        self.pinnedByUserLogin = pinnedByUserLogin
        self.pinnedByUserName = pinnedByUserName
        self.text = text
        self.fragments = fragments
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case broadcasterID = "broadcaster_id"
        case senderUserID = "sender_user_id"
        case senderUserLogin = "sender_user_login"
        case senderUserName = "sender_user_name"
        case pinnedByUserID = "pinned_by_user_id"
        case pinnedByUserLogin = "pinned_by_user_login"
        case pinnedByUserName = "pinned_by_user_name"
        case message
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messageID = try container.decode(String.self, forKey: .messageID)
        broadcasterID = try container.decode(String.self, forKey: .broadcasterID)
        senderUserID = try container.decode(String.self, forKey: .senderUserID)
        senderUserLogin = try container.decode(String.self, forKey: .senderUserLogin)
        senderUserName = try container.decode(String.self, forKey: .senderUserName)
        pinnedByUserID = try container.decode(String.self, forKey: .pinnedByUserID)
        pinnedByUserLogin = try container.decode(String.self, forKey: .pinnedByUserLogin)
        pinnedByUserName = try container.decode(String.self, forKey: .pinnedByUserName)
        let payload = try container.decodeIfPresent(PinnedPayload.self, forKey: .message)
        text = payload?.text
        fragments = payload?.fragments.map(Self.fragment) ?? []
        startsAt = try container.decode(Date.self, forKey: .startsAt)
        endsAt = Self.date(from: try container.decodeIfPresent(String.self, forKey: .endsAt))
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    private static func date(from raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return TwitchJSON.date(from: raw)
    }

    private static func fragment(from raw: PinnedFragment) -> ChatFragment {
        switch raw.type {
        case "emote":
            guard let emote = raw.emote else { return .text(raw.text) }
            return .emote(TwitchEmoteRef(
                id: emote.id,
                text: raw.text,
                setID: emote.setID.isEmpty ? nil : emote.setID,
                ownerID: emote.ownerID.isEmpty ? nil : emote.ownerID,
                formats: emote.format.compactMap(EmoteFormat.init(rawValue:))
            ))
        case "cheermote":
            guard let cheer = raw.cheermote else { return .text(raw.text) }
            return .cheermote(CheermoteRef(prefix: cheer.prefix, bits: cheer.bits, tier: cheer.tier, text: raw.text))
        case "mention":
            guard let mention = raw.mention else { return .text(raw.text) }
            return .mention(MentionRef(userID: mention.userID, login: mention.login, displayName: mention.name))
        default:
            return .text(raw.text)
        }
    }
}

private struct PinnedPayload: Decodable, Sendable {
    let text: String?
    let fragments: [PinnedFragment]
}

private struct PinnedFragment: Decodable, Sendable {
    let type: String
    let text: String
    let emote: Emote?
    let cheermote: Cheermote?
    let mention: Mention?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        emote = try container.decodeIfPresent(Emote.self, forKey: .emote)
        cheermote = try container.decodeIfPresent(Cheermote.self, forKey: .cheermote)
        mention = try container.decodeIfPresent(Mention.self, forKey: .mention)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case emote
        case cheermote
        case mention
    }

    struct Emote: Decodable, Sendable {
        let id: String
        let setID: String
        let ownerID: String
        let format: [String]

        enum CodingKeys: String, CodingKey {
            case id
            case setID = "emote_set_id"
            case ownerID = "owner_id"
            case format
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            setID = try container.decodeIfPresent(String.self, forKey: .setID) ?? ""
            ownerID = try container.decodeIfPresent(String.self, forKey: .ownerID) ?? ""
            format = try container.decodeIfPresent([String].self, forKey: .format) ?? []
        }
    }

    struct Cheermote: Decodable, Sendable {
        let prefix: String
        let bits: Int
        let tier: Int
    }

    struct Mention: Decodable, Sendable {
        let userID: String
        let login: String
        let name: String

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case login = "user_login"
            case name = "user_name"
        }
    }
}
