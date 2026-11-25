import Foundation
import EmbrCore

enum ChatCommands {
    static let specs: [CommandSpec] = [
        send,
        settings,
        set,
        emotesGlobal,
        emotesChannel,
        emotesUser,
        badgesGlobal,
        badgesChannel,
        chatters,
        pin,
        updatePin,
        unpin,
        shoutout,
        history
    ]

    static let send = CommandSpec(
        ["chat", "send"],
        summary: "Send a chat message as the signed-in user.",
        positionals: [
            PositionalSpec("channel", "Channel login or id."),
            PositionalSpec("message", "Message text; `-` reads stdin.", variadic: true)
        ],
        options: [.value("reply-to", "ID", "Reply to this message id.")],
        examples: [
            "embr chat send xqc hello",
            "echo 'hi' | embr chat send xqc -"
        ],
        scopes: ["user:write:chat"],
        mutating: true
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let senderID = try await context.userID()
        let message = try context.readMessage(Array(invocation.positionals.dropFirst()))
        guard !message.isEmpty else {
            throw CLIError.usage("The message is empty.")
        }
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.sendChatMessage(
            broadcasterID: broadcaster.id,
            senderID: senderID,
            message: message,
            replyParentMessageID: invocation.value("reply-to"),
            token: token
        )
        let response = try await context.send(request)
        let result = try HelixDecoder.sendResult(response.body)
        guard let result else {
            throw CLIError(.decode, "Twitch sent no message result.")
        }
        return CommandResult(SendView(channel: broadcaster.login, result: result), count: 1)
    }

    static let settings = CommandSpec(
        ["chat", "settings"],
        summary: "Read a channel's chat modes.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        options: [.value("as", "USER", "Moderator identity (default: you).")],
        examples: ["embr chat settings xqc"],
        scopes: ["moderator:manage:chat_settings"]
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let moderatorID = try await context.moderatorID(invocation.value("as"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.chatSettings(broadcasterID: broadcaster.id, moderatorID: moderatorID, token: token)
        let response = try await context.send(request)
        guard let state = try HelixDecoder.chatSettings(response.body) else {
            throw CLIError.notFound("Twitch returned no chat settings for \(broadcaster.login).")
        }
        return CommandResult(SettingsView(channel: broadcaster.login, settings: state), count: 1)
    }

    static let set = CommandSpec(
        ["chat", "set"],
        summary: "Change chat modes (emote-only, followers-only, slow, subscribers-only).",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        options: [
            .value("emote-only", "on|off", "Emote-only mode."),
            .value("followers-only", "off|MINUTES", "Followers-only mode."),
            .value("slow", "off|SECONDS", "Slow mode."),
            .value("subs-only", "on|off", "Subscribers-only mode."),
            .value("as", "USER", "Moderator identity (default: you).")
        ],
        examples: [
            "embr chat set xqc --emote-only on",
            "embr chat set xqc --slow 30 --followers-only 10"
        ],
        scopes: ["moderator:manage:chat_settings"],
        mutating: true
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let moderatorID = try await context.moderatorID(invocation.value("as"))
        var changes: [(String, ChatModeChange)] = []
        if let value = invocation.value("emote-only") {
            changes.append(("emote-only", .emoteOnly(try CommandSupport.onOff(value, "emote-only"))))
        }
        if let value = invocation.value("subs-only") {
            changes.append(("subs-only", .subscribersOnly(try CommandSupport.onOff(value, "subs-only"))))
        }
        if let value = invocation.value("followers-only") {
            let minutes = value.lowercased() == "off" ? nil : try intValue(value, "followers-only")
            changes.append(("followers-only", .followersOnly(minutes: minutes)))
        }
        if let value = invocation.value("slow") {
            let seconds = value.lowercased() == "off" ? nil : try intValue(value, "slow")
            changes.append(("slow", .slow(seconds: seconds)))
        }
        guard !changes.isEmpty else {
            throw CLIError.usage("Nothing to change.", hint: "Pass --emote-only, --followers-only, --slow or --subs-only.")
        }
        let factory = try context.factory()
        let token = try context.token()
        for (_, change) in changes {
            let request = factory.updateChatSettings(broadcasterID: broadcaster.id, moderatorID: moderatorID, change: change, token: token)
            let response = try await context.send(request)
            guard response.status == 200 || response.status == 204 else {
                throw CLIError.http(status: response.status, body: response.body)
            }
        }
        let stateRequest = factory.chatSettings(broadcasterID: broadcaster.id, moderatorID: moderatorID, token: token)
        let stateResponse = try await context.send(stateRequest)
        let state = try HelixDecoder.chatSettings(stateResponse.body)
        return CommandResult(
            SettingsChangeView(channel: broadcaster.login, changed: changes.map(\.0), settings: state),
            count: changes.count
        )
    }

    static let emotesGlobal = CommandSpec(
        ["chat", "emotes", "global"],
        summary: "Twitch's global emote set.",
        examples: ["embr chat emotes global --json"],
        scopes: ["any app or user token"]
    ) { _, context in
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.globalEmotes(token: token)
        let response = try await context.send(request)
        let page = try HelixDecoder.emotes(response.body)
        let views = page.data.map(EmoteView.init)
        return CommandSupport.list(views, table: emoteTable(views), cursor: page.pagination?.cursor)
    }

    static let emotesChannel = CommandSpec(
        ["chat", "emotes", "channel"],
        summary: "A channel's emotes.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        examples: ["embr chat emotes channel xqc"],
        scopes: ["any app or user token"]
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.channelEmotes(broadcasterID: broadcaster.id, token: token)
        let response = try await context.send(request)
        let page = try HelixDecoder.emotes(response.body)
        let views = page.data.map(EmoteView.init)
        return CommandSupport.list(views, table: emoteTable(views), cursor: page.pagination?.cursor)
    }

    static let emotesUser = CommandSpec(
        ["chat", "emotes", "user"],
        summary: "Every emote the user can use, with its set and type.",
        positionals: [PositionalSpec("user", "User login or id (default: you).", required: false)],
        options: [.value("broadcaster", "CHANNEL", "Add this channel's follower emotes to the first page.")],
        examples: ["embr chat emotes user --all --json"],
        scopes: ["user:read:emotes"]
    ) { invocation, context in
        let input: String
        if let named = invocation.optional(0) {
            input = named
        } else {
            input = try await context.login()
        }
        let userID = try await context.resolver.userID(input)
        let broadcasterID: String?
        if let channel = invocation.value("broadcaster") {
            broadcasterID = try await context.resolver.userID(channel)
        } else {
            broadcasterID = nil
        }
        let factory = try context.factory()
        let token = try context.token()
        let first = factory.userEmotes(userID: userID, broadcasterID: broadcasterID, after: context.options.after, token: token)
        let (items, cursor) = try await context.collect(first, decode: UserEmoteDecoder.decode) { after in
            factory.userEmotes(userID: userID, broadcasterID: broadcasterID, after: after, token: token)
        }
        let views = items.map(UserEmoteView.init)
        let table = CommandSupport.table(
            ["PROVIDER", "NAME", "ID", "TYPE", "SET"],
            views.map { ["Twitch", $0.name, $0.id, $0.emoteType, $0.setID ?? ""] }
        )
        return CommandSupport.list(views, table: table, cursor: cursor)
    }

    static let badgesGlobal = CommandSpec(
        ["chat", "badges", "global"],
        summary: "Twitch's global chat badges.",
        examples: ["embr chat badges global --json"],
        scopes: ["any app or user token"]
    ) { _, context in
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.globalBadges(token: token)
        let response = try await context.send(request)
        let page = try HelixDecoder.badges(response.body)
        let views = page.data.map(BadgeView.init)
        return CommandSupport.list(views, table: badgeTable(views), cursor: page.pagination?.cursor)
    }

    static let badgesChannel = CommandSpec(
        ["chat", "badges", "channel"],
        summary: "A channel's chat badges.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        examples: ["embr chat badges channel xqc"],
        scopes: ["any app or user token"]
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.channelBadges(broadcasterID: broadcaster.id, token: token)
        let response = try await context.send(request)
        let page = try HelixDecoder.badges(response.body)
        let views = page.data.map(BadgeView.init)
        return CommandSupport.list(views, table: badgeTable(views), cursor: page.pagination?.cursor)
    }

    static let chatters = CommandSpec(
        ["chat", "chatters"],
        summary: "Users connected to a channel's chat right now.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        options: [.value("as", "USER", "Moderator identity (default: you).")],
        examples: ["embr chat chatters xqc --all --json"],
        scopes: ["moderator:read:chatters"]
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let moderatorID = try await context.moderatorID(invocation.value("as"))
        let factory = try context.factory()
        let token = try context.token()
        let first = invocation.int("first") ?? context.options.first ?? 100
        let request = factory.chatters(broadcasterID: broadcaster.id, moderatorID: moderatorID, first: first, after: context.options.after, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }
        let (items, cursor) = try await context.collect(request, decode: { try TwitchJSON.decoder.decode(HelixResponse<ChannelUser>.self, from: $0) }) { after in
            factory.chatters(broadcasterID: broadcaster.id, moderatorID: moderatorID, first: first, after: after, token: token)
        }
        let views = items.map(ChannelUserView.init)
        let table = CommandSupport.table(
            ["LOGIN", "NAME", "ID"],
            views.map { [$0.userLogin, $0.userName, $0.userID] }
        )
        return CommandSupport.list(views, table: table, cursor: cursor)
    }

    static let pin = CommandSpec(
        ["chat", "pin"],
        summary: "Pin a message in a channel's chat.",
        positionals: [
            PositionalSpec("channel", "Channel login or id."),
            PositionalSpec("message-id", "Message id to pin.")
        ],
        options: [
            .value("duration", "SECONDS", "Pin duration, 30…1800 (default: until stream ends).", range: 30...1800),
            .value("as", "USER", "Moderator identity (default: you).")
        ],
        examples: ["embr chat pin xqc 1234-5678 --duration 600"],
        scopes: ["moderator:manage:chat_messages"],
        mutating: true
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let messageID = try invocation.require(1, "message id")
        let moderatorID = try await context.moderatorID(invocation.value("as"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.pinMessage(
            broadcasterID: broadcaster.id,
            moderatorID: moderatorID,
            messageID: messageID,
            durationSeconds: invocation.int("duration"),
            token: token
        )
        let response = try await context.send(request)
        guard response.status == 204 else {
            throw CLIError.http(status: response.status, body: response.body)
        }
        return CommandResult(PinView(channel: broadcaster.login, messageID: messageID, pinned: true))
    }

    static let updatePin = CommandSpec(
        ["chat", "update-pin"],
        summary: "Change how long a pinned message stays up.",
        positionals: [
            PositionalSpec("channel", "Channel login or id."),
            PositionalSpec("message-id", "Pinned message id.")
        ],
        options: [
            .value("duration", "SECONDS", "New duration, 30…1800 (default: until stream ends).", range: 30...1800),
            .value("as", "USER", "Moderator identity (default: you).")
        ],
        examples: ["embr chat update-pin xqc 1234-5678 --duration 900"],
        scopes: ["moderator:manage:chat_messages"],
        mutating: true
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let messageID = try invocation.require(1, "message id")
        let moderatorID = try await context.moderatorID(invocation.value("as"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.updatePinnedMessage(
            broadcasterID: broadcaster.id,
            moderatorID: moderatorID,
            messageID: messageID,
            durationSeconds: invocation.int("duration"),
            token: token
        )
        let response = try await context.send(request)
        guard response.status == 204 else {
            throw CLIError.http(status: response.status, body: response.body)
        }
        return CommandResult(PinView(channel: broadcaster.login, messageID: messageID, pinned: true))
    }

    static let unpin = CommandSpec(
        ["chat", "unpin"],
        summary: "Unpin the channel's pinned message.",
        positionals: [
            PositionalSpec("channel", "Channel login or id."),
            PositionalSpec("message-id", "Pinned message id.")
        ],
        options: [.value("as", "USER", "Moderator identity (default: you).")],
        examples: ["embr chat unpin xqc 1234-5678"],
        scopes: ["moderator:manage:chat_messages"],
        mutating: true
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let messageID = try invocation.require(1, "message id")
        let moderatorID = try await context.moderatorID(invocation.value("as"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.unpinMessage(
            broadcasterID: broadcaster.id,
            moderatorID: moderatorID,
            messageID: messageID,
            token: token
        )
        let response = try await context.send(request)
        guard response.status == 204 else {
            throw CLIError.http(status: response.status, body: response.body)
        }
        return CommandResult(PinView(channel: broadcaster.login, messageID: messageID, pinned: false))
    }

    static let shoutout = CommandSpec(
        ["chat", "shoutout"],
        summary: "Send a shoutout from your channel to another.",
        positionals: [
            PositionalSpec("from", "Channel sending the shoutout; must be yours."),
            PositionalSpec("to", "Channel receiving it.")
        ],
        examples: ["embr chat shoutout mychannel friendchannel"],
        scopes: ["moderator:manage:shoutouts"],
        mutating: true
    ) { invocation, context in
        let from = try await context.resolver.user(try invocation.require(0, "from"))
        let to = try await context.resolver.user(try invocation.require(1, "to"))
        let moderatorID = try await context.moderatorID(nil)
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.shoutout(
            fromBroadcasterID: from.id,
            toBroadcasterID: to.id,
            moderatorID: moderatorID,
            token: token
        )
        let response = try await context.send(request)
        guard response.status == 204 else {
            throw CLIError.http(status: response.status, body: response.body)
        }
        return CommandResult(ShoutoutView(from: from.login, to: to.login, sent: true))
    }

    static let history = CommandSpec(
        ["chat", "history"],
        summary: "Recent chat messages for a channel (recent-messages service).",
        details: "Reads recent-messages.robotty.de; no Twitch token is needed.",
        positionals: [PositionalSpec("channel", "Channel login.")],
        options: [.value("limit", "N", "Messages to ask for, 1…800.", defaultValue: "100", range: 1...800)],
        examples: ["embr chat history xqc --limit 50"],
        needsAuth: false
    ) { invocation, context in
        let channel = try invocation.require(0, "channel").lowercased()
        let limit = invocation.int("limit") ?? 100
        guard let url = URL(string: "https://recent-messages.robotty.de/api/v2/recent-messages/\(channel)?limit=\(limit)") else {
            throw CLIError.usage("Invalid channel name.")
        }
        let response = try await context.send(HTTPRequest(method: .get, url: url))
        if context.options.raw {
            return CommandResult(try context.rawValue(response))
        }
        let messages = RecentMessagesParser.messages(fromJSON: response.body, channelID: channel)
        let views = messages.map(HistoryView.init)
        let table = CommandSupport.table(
            ["TIME", "AUTHOR", "TEXT"],
            views.map { [$0.timestamp, $0.author, $0.text] }
        )
        return CommandSupport.list(views, table: table, cursor: nil)
    }

    private static func intValue(_ raw: String, _ name: String) throws -> Int {
        guard let value = Int(raw), value > 0 else {
            throw CLIError.usage("`--\(name)` takes a positive number or off.")
        }
        return value
    }

    private static func emoteTable(_ emotes: [EmoteView]) -> TableData {
        CommandSupport.table(
            ["PROVIDER", "NAME", "ID", "ANIMATED"],
            emotes.map { ["Twitch", $0.name, $0.id, CommandSupport.yesNo($0.animated)] }
        )
    }

    private static func badgeTable(_ badges: [BadgeView]) -> TableData {
        CommandSupport.table(
            ["SET", "VERSION", "TITLE"],
            badges.map { [$0.setID, $0.version, $0.title] }
        )
    }
}

struct EmoteView: Encodable {
    let id: String
    let name: String
    let provider: String
    let animated: Bool
    let images: [String: String]

    init(_ emote: Emote) {
        id = emote.id
        name = emote.name
        provider = emote.provider.rawValue
        animated = emote.isAnimated
        images = Dictionary(uniqueKeysWithValues: emote.images.urlsByScale.map { ("\($0.key.rawValue)", $0.value.absoluteString) })
    }

    init(user emote: UserEmote) {
        self.init(emote.emote)
    }
}

struct UserEmoteView: Encodable {
    let id: String
    let name: String
    let provider: String
    let animated: Bool
    let emoteType: String
    let setID: String?
    let ownerID: String?
    let images: [String: String]

    init(_ emote: UserEmote) {
        id = emote.id
        name = emote.name
        provider = emote.emote.provider.rawValue
        animated = emote.isAnimated
        emoteType = emote.emoteType
        setID = emote.setID
        ownerID = emote.ownerID
        images = Dictionary(uniqueKeysWithValues: emote.emote.images.urlsByScale.map { ("\($0.key.rawValue)", $0.value.absoluteString) })
    }
}

struct BadgeView: Encodable {
    let id: String
    let setID: String
    let version: String
    let title: String
    let provider: String
    let images: [String: String]

    init(_ badge: Badge) {
        id = badge.id
        setID = badge.setID
        version = badge.version
        title = badge.title
        provider = badge.provider.rawValue
        images = Dictionary(uniqueKeysWithValues: badge.images.urlsByScale.map { ("\($0.key.rawValue)", $0.value.absoluteString) })
    }
}

private struct SendView: Encodable {
    let channel: String
    let result: SendResult
}

private struct SettingsView: Encodable {
    let channel: String
    let settings: RoomState
}

private struct SettingsChangeView: Encodable {
    let channel: String
    let changed: [String]
    let settings: RoomState?
}

private struct PinView: Encodable {
    let channel: String
    let messageID: String
    let pinned: Bool
}

private struct ShoutoutView: Encodable {
    let from: String
    let to: String
    let sent: Bool
}

private struct HistoryView: Encodable {
    let id: String
    let timestamp: String
    let author: String
    let text: String
    let badges: [String]

    init(_ message: ChatMessage) {
        id = message.id
        timestamp = CommandSupport.timestamp(message.timestamp)
        author = message.author.login
        text = message.plainText
        badges = message.badges.map { "\($0.setID)/\($0.id)" }
    }
}
