import Foundation

public enum EventSubMessage: Sendable, Equatable {
    case welcome(sessionID: String, keepaliveSeconds: Int?)
    case keepalive
    case notification(subscriptionType: String, event: Data)
    case reconnect(url: String)
    case revocation(reason: String)

    public static func decode(_ data: Data) throws -> EventSubMessage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decoding("EventSub envelope is not a JSON object")
        }
        guard let metadata = root["metadata"] as? [String: Any],
              let messageType = metadata["message_type"] as? String else {
            throw APIError.decoding("EventSub envelope missing metadata.message_type")
        }
        let payload = root["payload"] as? [String: Any] ?? [:]

        switch messageType {
        case "session_welcome":
            return try decodeWelcome(payload)
        case "session_keepalive":
            return .keepalive
        case "notification":
            return try decodeNotification(metadata: metadata, payload: payload)
        case "session_reconnect":
            return try decodeReconnect(payload)
        case "revocation":
            return decodeRevocation(payload)
        default:
            throw APIError.decoding("Unknown EventSub message_type: \(messageType)")
        }
    }

    private static func decodeWelcome(_ payload: [String: Any]) throws -> EventSubMessage {
        guard let session = payload["session"] as? [String: Any],
              let id = session["id"] as? String else {
            throw APIError.decoding("session_welcome missing payload.session.id")
        }
        let keepalive = (session["keepalive_timeout_seconds"] as? NSNumber)?.intValue
        return .welcome(sessionID: id, keepaliveSeconds: keepalive)
    }

    private static func decodeReconnect(_ payload: [String: Any]) throws -> EventSubMessage {
        guard let session = payload["session"] as? [String: Any],
              let url = session["reconnect_url"] as? String else {
            throw APIError.decoding("session_reconnect missing payload.session.reconnect_url")
        }
        return .reconnect(url: url)
    }

    private static func decodeNotification(metadata: [String: Any], payload: [String: Any]) throws -> EventSubMessage {
        let subscription = payload["subscription"] as? [String: Any]
        let type = (subscription?["type"] as? String)
            ?? (metadata["subscription_type"] as? String)
        guard let subscriptionType = type else {
            throw APIError.decoding("notification missing subscription.type")
        }
        guard let event = payload["event"] else {
            throw APIError.decoding("notification missing payload.event")
        }
        let eventData = try JSONSerialization.data(withJSONObject: event)
        return .notification(subscriptionType: subscriptionType, event: eventData)
    }

    private static func decodeRevocation(_ payload: [String: Any]) -> EventSubMessage {
        let subscription = payload["subscription"] as? [String: Any]
        let reason = (subscription?["status"] as? String) ?? "unknown"
        return .revocation(reason: reason)
    }
}
