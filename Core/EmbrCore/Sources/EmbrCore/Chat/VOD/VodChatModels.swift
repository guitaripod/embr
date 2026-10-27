import Foundation

public struct VodCommentFragment: Sendable, Equatable, Decodable {
    public let text: String
    public let emoteID: String?

    public init(text: String, emoteID: String? = nil) {
        self.text = text
        self.emoteID = emoteID
    }
}

public struct VodComment: Sendable, Equatable, Decodable, Identifiable {
    public let id: String
    public let offsetSeconds: Int
    public let createdAt: Date
    public let authorID: String
    public let authorLogin: String
    public let authorName: String
    public let color: String?
    public let fragments: [VodCommentFragment]

    public init(
        id: String,
        offsetSeconds: Int,
        createdAt: Date,
        authorID: String,
        authorLogin: String,
        authorName: String,
        color: String? = nil,
        fragments: [VodCommentFragment]
    ) {
        self.id = id
        self.offsetSeconds = offsetSeconds
        self.createdAt = createdAt
        self.authorID = authorID
        self.authorLogin = authorLogin
        self.authorName = authorName
        self.color = color
        self.fragments = fragments
    }
}

public struct VodCommentsPage: Sendable, Equatable, Decodable {
    public let comments: [VodComment]
    public let nextOffset: Int
    public let hasMore: Bool

    public init(comments: [VodComment], nextOffset: Int, hasMore: Bool) {
        self.comments = comments
        self.nextOffset = nextOffset
        self.hasMore = hasMore
    }
}

public extension VodComment {
    /// Twitch sends the emote and its character range in one field (`id;start;end`), while the
    /// chat renderer keys emotes by the bare id.
    func chatMessage(channelID: String) -> ChatMessage {
        let chatFragments = fragments.compactMap { fragment -> ChatFragment? in
            guard !fragment.text.isEmpty else { return nil }
            guard let emoteID = fragment.emoteID else { return .text(fragment.text) }
            let bareID = emoteID.split(separator: ";", maxSplits: 1).first.map(String.init) ?? emoteID
            return .emote(TwitchEmoteRef(id: bareID, text: fragment.text, formats: [.static]))
        }
        return ChatMessage(
            id: id,
            channelID: channelID,
            timestamp: createdAt,
            author: ChatUser(
                id: authorID,
                login: authorLogin,
                displayName: authorName,
                color: color.flatMap(ChatColor.init(hex:))
            ),
            fragments: chatFragments
        )
    }
}
