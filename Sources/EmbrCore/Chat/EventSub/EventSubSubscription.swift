import Foundation

public struct EventSubSubscriptionRequest: Encodable, Sendable, Equatable {
    public let type: String
    public let version: String
    public let condition: [String: String]
    public let transport: Transport

    public struct Transport: Encodable, Sendable, Equatable {
        public let method: String
        public let sessionID: String

        public init(method: String = "websocket", sessionID: String) {
            self.method = method
            self.sessionID = sessionID
        }

        enum CodingKeys: String, CodingKey {
            case method
            case sessionID = "session_id"
        }
    }

    public init(type: String, version: String = "1", condition: [String: String], transport: Transport) {
        self.type = type
        self.version = version
        self.condition = condition
        self.transport = transport
    }

    public static func chatMessage(broadcasterID: String, userID: String, sessionID: String) -> EventSubSubscriptionRequest {
        chat(type: "channel.chat.message", broadcasterID: broadcasterID, userID: userID, sessionID: sessionID)
    }

    public static func chatNotification(broadcasterID: String, userID: String, sessionID: String) -> EventSubSubscriptionRequest {
        chat(type: "channel.chat.notification", broadcasterID: broadcasterID, userID: userID, sessionID: sessionID)
    }

    public static func chatMessageDelete(broadcasterID: String, userID: String, sessionID: String) -> EventSubSubscriptionRequest {
        chat(type: "channel.chat.message_delete", broadcasterID: broadcasterID, userID: userID, sessionID: sessionID)
    }

    public static func chatClearUserMessages(broadcasterID: String, userID: String, sessionID: String) -> EventSubSubscriptionRequest {
        chat(type: "channel.chat.clear_user_messages", broadcasterID: broadcasterID, userID: userID, sessionID: sessionID)
    }

    public static func chatClear(broadcasterID: String, userID: String, sessionID: String) -> EventSubSubscriptionRequest {
        chat(type: "channel.chat.clear", broadcasterID: broadcasterID, userID: userID, sessionID: sessionID)
    }

    public static func supplementalChatSubscriptions(broadcasterID: String, userID: String, sessionID: String) -> [EventSubSubscriptionRequest] {
        [
            chatNotification(broadcasterID: broadcasterID, userID: userID, sessionID: sessionID),
            chatMessageDelete(broadcasterID: broadcasterID, userID: userID, sessionID: sessionID),
            chatClearUserMessages(broadcasterID: broadcasterID, userID: userID, sessionID: sessionID),
            chatClear(broadcasterID: broadcasterID, userID: userID, sessionID: sessionID),
        ]
    }

    private static func chat(type: String, broadcasterID: String, userID: String, sessionID: String) -> EventSubSubscriptionRequest {
        EventSubSubscriptionRequest(
            type: type,
            version: "1",
            condition: [
                "broadcaster_user_id": broadcasterID,
                "user_id": userID,
            ],
            transport: Transport(sessionID: sessionID)
        )
    }

    public func encoded() throws -> Data {
        try TwitchJSON.encoder.encode(self)
    }
}
