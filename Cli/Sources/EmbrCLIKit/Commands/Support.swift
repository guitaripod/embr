import Foundation
import EmbrCore

enum ScopePreset {
    static let chat = [
        "chat:read", "chat:edit", "user:read:chat", "user:write:chat"
    ]
    static let moderation = [
        "moderator:read:chatters",
        "moderator:manage:banned_users",
        "moderator:manage:chat_messages",
        "moderator:read:chat_messages",
        "moderator:manage:chat_settings",
        "moderator:manage:automod",
        "moderator:manage:unban_requests",
        "moderator:manage:shoutouts",
        "moderator:manage:shield_mode",
        "moderator:read:shield_mode",
        "moderator:read:followers",
        "moderation:read",
        "user:read:moderated_channels"
    ]
    static let studio = [
        "channel:read:ads",
        "channel:manage:ads",
        "channel:edit:commercial",
        "channel:read:polls",
        "channel:read:predictions",
        "channel:read:hype_train",
        "channel:read:goals",
        "channel:read:redemptions",
        "bits:read",
        "channel:read:subscriptions"
    ]
    static let channel = [
        "channel:manage:broadcast",
        "channel:read:vips",
        "channel:manage:vips"
    ]
    static let user = [
        "user:read:emotes",
        "user:read:follows",
        "user:read:blocked_users",
        "user:manage:blocked_users"
    ]

    static let all = Array(Set(chat + moderation + studio + channel + user)).sorted()

    static func expand(_ value: String) throws -> [String] {
        var scopes: [String] = []
        for raw in value.split(separator: ",").map(String.init) {
            let name = raw.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            switch name {
            case "chat": scopes += chat
            case "mod": scopes += moderation
            case "studio": scopes += studio
            case "channel": scopes += channel
            case "user": scopes += user
            case "all": scopes += all
            default:
                if name.contains(":") {
                    scopes.append(name)
                } else {
                    throw CLIError.usage(
                        "Unknown scope preset `\(name)`.",
                        hint: "Use chat, mod, studio, channel, user, all, or explicit scopes such as chat:read."
                    )
                }
            }
        }
        var seen = Set<String>()
        return scopes.filter { seen.insert($0).inserted }
    }
}

enum CommandSupport {
    static func onOff(_ value: String, _ name: String) throws -> Bool {
        switch value.lowercased() {
        case "on", "true", "yes", "1": return true
        case "off", "false", "no", "0": return false
        default:
            throw CLIError.usage("`--\(name)` must be on or off.")
        }
    }

    static func table(_ columns: [String], _ rows: [[String]]) -> TableData {
        TableData(columns: columns, rows: rows)
    }

    nonisolated(unsafe) private static let iso = ISO8601DateFormatter()

    static func timestamp(_ date: Date?) -> String {
        guard let date else { return "" }
        return iso.string(from: date)
    }

    static func requireAnyFlag(_ invocation: Invocation, _ names: [String]) throws {
        guard names.contains(where: { invocation.value($0) != nil }) else {
            throw CLIError.usage(
                "Nothing to change.",
                hint: "Pass at least one of: \(names.map { "--\($0)" }.joined(separator: ", "))."
            )
        }
    }

    static func list<T: Encodable & Sendable>(
        _ items: [T],
        table: TableData?,
        cursor: String?,
        total: Int? = nil
    ) -> CommandResult {
        CommandResult(
            items,
            items: items.map { AnyEncodable($0) },
            table: table,
            cursor: cursor,
            total: total,
            count: items.count
        )
    }

    static func raw(_ request: HTTPRequest, _ context: RunContext) async throws -> CommandResult? {
        guard context.options.raw else { return nil }
        let response = try await context.send(request)
        return CommandResult(try context.rawValue(response))
    }

    static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }
}
