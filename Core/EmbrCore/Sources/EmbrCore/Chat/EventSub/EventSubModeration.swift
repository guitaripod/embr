import Foundation

/// Reads the moderator EventSub events (AutoMod holds and their outcome, channel.moderate v2, unban requests) into
/// ``ModerationEvent``s.
enum EventSubModeration {
    static let types: Set<String> = ["automod.message.hold", "automod.message.update", "channel.moderate", "channel.unban_request.create"]

    static func event(subscriptionType: String, eventData: Data, timestamp: Date) throws -> ModerationEvent {
        switch subscriptionType {
        case "automod.message.hold":
            let event = try TwitchJSON.decode(HoldEvent.self, from: eventData)
            return .held(HeldMessage(
                id: event.messageID,
                author: ChatUser(id: event.userID, login: event.userLogin, displayName: event.userName),
                text: event.message.text,
                reason: event.reason == "blocked_term" ? "blocked term" : (event.automod?.category ?? event.reason ?? "automod"),
                heldAt: event.heldAt ?? timestamp
            ))
        case "automod.message.update":
            let event = try TwitchJSON.decode(UpdateEvent.self, from: eventData)
            let status = HeldMessage.Status(rawValue: event.status.lowercased()) ?? .expired
            return .heldResolved(messageID: event.messageID, status: status, moderator: event.moderatorUserName)
        case "channel.moderate":
            return .action(try logEntry(eventData, timestamp: timestamp))
        case "channel.unban_request.create":
            let event = try TwitchJSON.decode(UnbanRequestEvent.self, from: eventData)
            return .unbanRequest(UnbanRequest(
                id: event.id,
                user: ChatUser(id: event.userID, login: event.userLogin, displayName: event.userName),
                text: event.text,
                createdAt: event.createdAt ?? timestamp
            ))
        default:
            throw APIError.decoding("Unsupported moderation subscription type: \(subscriptionType)")
        }
    }

    /// One channel.moderate event: the action names an object of the same name (ban, timeout, followers, …) that
    /// carries who it targeted and its details; settings such as emote-only carry none.
    private static func logEntry(_ data: Data, timestamp: Date) throws -> ModerationLogEntry {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = root["action"] as? String else {
            throw APIError.decoding("channel.moderate without an action")
        }
        let details = root[action] as? [String: Any] ?? [:]
        let target = (details["user_name"] as? String) ?? (details["user_login"] as? String)
        var seconds: Int?
        if let expires = (details["expires_at"] as? String).flatMap(parseDate) {
            seconds = max(0, Int(expires.timeIntervalSince(timestamp).rounded()))
        } else if let wait = details["wait_time_seconds"] as? Int {
            seconds = wait
        } else if let minutes = details["follow_duration_minutes"] as? Int {
            seconds = minutes * 60
        }
        return ModerationLogEntry(
            action: action,
            moderator: (root["moderator_user_name"] as? String) ?? (root["moderator_user_login"] as? String) ?? "",
            target: target,
            reason: (details["reason"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            seconds: seconds,
            messageText: details["message_body"] as? String,
            at: timestamp
        )
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private struct HoldEvent: Decodable {
        struct Message: Decodable { let text: String }
        struct AutoMod: Decodable { let category: String? }
        let userID: String
        let userLogin: String
        let userName: String
        let messageID: String
        let message: Message
        let reason: String?
        let automod: AutoMod?
        let heldAt: Date?

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case userLogin = "user_login"
            case userName = "user_name"
            case messageID = "message_id"
            case message
            case reason
            case automod
            case heldAt = "held_at"
        }
    }

    private struct UpdateEvent: Decodable {
        let messageID: String
        let status: String
        let moderatorUserName: String?

        enum CodingKeys: String, CodingKey {
            case messageID = "message_id"
            case status
            case moderatorUserName = "moderator_user_name"
        }
    }

    private struct UnbanRequestEvent: Decodable {
        let id: String
        let userID: String
        let userLogin: String
        let userName: String
        let text: String
        let createdAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case userID = "user_id"
            case userLogin = "user_login"
            case userName = "user_name"
            case text
            case createdAt = "created_at"
        }
    }
}
