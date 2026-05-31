import Foundation

public enum ChatEvent: Sendable, Equatable {
    case message(ChatMessage)
    case deleteMessage(messageID: String)
    case clearUserMessages(userID: String, login: String)
    case clearChat
    case roomState(RoomState)
    case notice(SystemNotice)
    case connection(ConnectionStatus)
}

public struct SystemNotice: Sendable, Equatable {
    public let messageID: String?
    public let text: String
    public let isError: Bool

    public init(messageID: String? = nil, text: String, isError: Bool = false) {
        self.messageID = messageID
        self.text = text
        self.isError = isError
    }
}

public enum ConnectionStatus: Sendable, Equatable {
    case idle
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case disconnected(reason: String?)
}

public struct RoomState: Sendable, Equatable {
    public var emoteOnly: Bool
    public var followersOnly: Int?
    public var subscribersOnly: Bool
    public var slowMode: Int?
    public var uniqueChat: Bool

    public init(
        emoteOnly: Bool = false,
        followersOnly: Int? = nil,
        subscribersOnly: Bool = false,
        slowMode: Int? = nil,
        uniqueChat: Bool = false
    ) {
        self.emoteOnly = emoteOnly
        self.followersOnly = followersOnly
        self.subscribersOnly = subscribersOnly
        self.slowMode = slowMode
        self.uniqueChat = uniqueChat
    }
}

public struct SendResult: Sendable, Equatable {
    public let messageID: String?
    public let isSent: Bool
    public let dropReason: String?

    public init(messageID: String?, isSent: Bool, dropReason: String? = nil) {
        self.messageID = messageID
        self.isSent = isSent
        self.dropReason = dropReason
    }
}
