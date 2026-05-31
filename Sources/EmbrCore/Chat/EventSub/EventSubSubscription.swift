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
        EventSubSubscriptionRequest(
            type: "channel.chat.message",
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
