import Foundation
import EmbrCore

/// A moderated chat's pending work and history: messages AutoMod is holding, unban requests waiting for an answer,
/// and the moderation log, newest first.
struct ModerationQueue: Sendable {
    var held: [HeldMessage] = []
    var requests: [UnbanRequest] = []
    var log: [ModerationLogEntry] = []

    var isEmpty: Bool { held.isEmpty && requests.isEmpty && log.isEmpty }
}

extension ModerationLogEntry {
    /// The log line as a moderator reads it in chat: who did what to whom, for how long and why.
    var summary: String {
        let who = moderator.isEmpty ? String(localized: "A moderator") : moderator
        let whom = target ?? ""
        let base = action.hasPrefix("shared_chat_") ? String(action.dropFirst("shared_chat_".count)) : action
        var line: String
        switch base {
        case "ban": line = String(localized: "\(who) banned \(whom)")
        case "unban": line = String(localized: "\(who) unbanned \(whom)")
        case "timeout": line = seconds.map { String(localized: "\(who) timed out \(whom) for \(Self.duration($0))") } ?? String(localized: "\(who) timed out \(whom)")
        case "untimeout": line = String(localized: "\(who) lifted \(whom)'s timeout")
        case "delete": line = String(localized: "\(who) deleted a message from \(whom)")
        case "warn": line = String(localized: "\(who) warned \(whom)")
        case "mod": line = String(localized: "\(who) made \(whom) a moderator")
        case "unmod": line = String(localized: "\(who) removed \(whom) as a moderator")
        case "vip": line = String(localized: "\(who) made \(whom) a VIP")
        case "unvip": line = String(localized: "\(who) removed \(whom) as a VIP")
        case "raid": line = String(localized: "\(who) raided \(whom)")
        case "unraid": line = String(localized: "\(who) canceled the raid")
        case "clear": line = String(localized: "\(who) cleared chat")
        case "slow": line = seconds.map { String(localized: "\(who) turned on slow mode (\(Self.duration($0)))") } ?? String(localized: "\(who) turned on slow mode")
        case "slowoff": line = String(localized: "\(who) turned off slow mode")
        case "followers": line = String(localized: "\(who) turned on followers-only chat")
        case "followersoff": line = String(localized: "\(who) turned off followers-only chat")
        case "emoteonly": line = String(localized: "\(who) turned on emote-only chat")
        case "emoteonlyoff": line = String(localized: "\(who) turned off emote-only chat")
        case "subscribers": line = String(localized: "\(who) turned on subscribers-only chat")
        case "subscribersoff": line = String(localized: "\(who) turned off subscribers-only chat")
        case "uniquechat": line = String(localized: "\(who) turned on unique chat")
        case "uniquechatoff": line = String(localized: "\(who) turned off unique chat")
        case "automod_terms": line = String(localized: "\(who) changed AutoMod's terms")
        case "unban_request": line = String(localized: "\(who) answered \(whom)'s unban request")
        default: line = String(localized: "\(who) used \(action)")
        }
        if let reason { line += ": " + reason }
        return line
    }

    /// The log line as a chat row the moderation log draws in place.
    func chatRow(channelID: String) -> ChatMessage {
        ChatMessage(
            id: "modlog-\(UUID().uuidString)",
            channelID: channelID,
            timestamp: at,
            author: ChatUser(id: "", login: "", displayName: ""),
            fragments: [],
            notice: ChannelNotice(kind: .moderation, systemMessage: summary)
        )
    }

    private static func duration(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = [.weekOfMonth, .day, .hour, .minute, .second]
        return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds)s"
    }
}
