import Foundation

/// What a moderator sees happen in a channel they moderate: AutoMod holding a message for review and its outcome,
/// every moderation action anyone takes, and requests to be unbanned.
public enum ModerationEvent: Sendable, Equatable {
    case held(HeldMessage)
    case heldResolved(messageID: String, status: HeldMessage.Status, moderator: String?)
    case action(ModerationLogEntry)
    case unbanRequest(UnbanRequest)
}

/// A chat message AutoMod or a blocked term kept from the channel until a moderator allows or denies it.
public struct HeldMessage: Sendable, Equatable, Identifiable {
    public enum Status: String, Sendable, Equatable {
        case approved
        case denied
        case expired
    }

    public let id: String
    public let author: ChatUser
    public let text: String
    /// Why it was held: AutoMod's category ("aggressive", "swearing", …) or "blocked term".
    public let reason: String
    public let heldAt: Date

    public init(id: String, author: ChatUser, text: String, reason: String, heldAt: Date) {
        self.id = id
        self.author = author
        self.text = text
        self.reason = reason
        self.heldAt = heldAt
    }
}

/// One line of the moderation log: who did what to whom, and why.
public struct ModerationLogEntry: Sendable, Equatable {
    /// Twitch's action name: ban, timeout, unban, untimeout, delete, warn, mod, unmod, vip, unvip, raid, slow,
    /// followers, emoteonly, subscribers, uniquechat, clear, and their shared-chat forms.
    public let action: String
    public let moderator: String
    public let target: String?
    public let reason: String?
    /// A timeout's length, a slow mode's wait or followers-only's minimum follow time, in seconds.
    public let seconds: Int?
    /// The text of a deleted message.
    public let messageText: String?
    public let at: Date

    public init(action: String, moderator: String, target: String?, reason: String?, seconds: Int?, messageText: String?, at: Date) {
        self.action = action
        self.moderator = moderator
        self.target = target
        self.reason = reason
        self.seconds = seconds
        self.messageText = messageText
        self.at = at
    }
}

/// A banned user's request to be let back into chat.
public struct UnbanRequest: Sendable, Equatable, Identifiable {
    public let id: String
    public let user: ChatUser
    public let text: String
    public let createdAt: Date

    public init(id: String, user: ChatUser, text: String, createdAt: Date) {
        self.id = id
        self.user = user
        self.text = text
        self.createdAt = createdAt
    }
}
