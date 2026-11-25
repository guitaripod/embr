import Foundation
import EmbrCore

enum ModCommands {
    static let specs: [CommandSpec] = [
        ban,
        unban,
        deleteMessage,
        automod,
        resolveUnban,
        moderated,
        banned,
        moderators,
        vips
    ]

    static let ban = CommandSpec(
        ["mod", "ban"],
        summary: "Ban or time out a user.",
        positionals: [
            PositionalSpec("channel", "Channel login or id."),
            PositionalSpec("user", "User login or id to ban.")
        ],
        options: [
            .value("duration", "SECONDS", "Timeout length; omit for a permanent ban.", range: 1...1_209_600),
            .value("reason", "TEXT", "Reason shown in the moderation log."),
            .value("as", "USER", "Moderator identity (default: you).")
        ],
        examples: [
            "embr mod ban xqc spammer --reason spam --duration 600",
            "embr mod ban xqc spammer --reason \"ban evasion\""
        ],
        scopes: ["moderator:manage:banned_users"],
        mutating: true
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let target = try await context.resolver.user(try invocation.require(1, "user"))
        let moderatorID = try await context.moderatorID(invocation.value("as"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.banUser(
            broadcasterID: broadcaster.id,
            moderatorID: moderatorID,
            userID: target.id,
            duration: invocation.int("duration"),
            reason: invocation.value("reason"),
            token: token
        )
        let response = try await context.send(request)
        guard (200..<300).contains(response.status) else {
            throw CLIError.http(status: response.status, body: response.body)
        }
        return CommandResult(BanView(channel: broadcaster.login, user: target.login, banned: true, duration: invocation.int("duration")))
    }

    static let unban = CommandSpec(
        ["mod", "unban"],
        summary: "Remove a ban or timeout.",
        positionals: [
            PositionalSpec("channel", "Channel login or id."),
            PositionalSpec("user", "User login or id.")
        ],
        options: [.value("as", "USER", "Moderator identity (default: you).")],
        examples: ["embr mod unban xqc spammer"],
        scopes: ["moderator:manage:banned_users"],
        mutating: true
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let target = try await context.resolver.user(try invocation.require(1, "user"))
        let moderatorID = try await context.moderatorID(invocation.value("as"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.unbanUser(
            broadcasterID: broadcaster.id,
            moderatorID: moderatorID,
            userID: target.id,
            token: token
        )
        let response = try await context.send(request)
        guard response.status == 204 else {
            throw CLIError.http(status: response.status, body: response.body)
        }
        return CommandResult(BanView(channel: broadcaster.login, user: target.login, banned: false, duration: nil))
    }

    static let deleteMessage = CommandSpec(
        ["mod", "delete"],
        summary: "Delete one chat message.",
        positionals: [
            PositionalSpec("channel", "Channel login or id."),
            PositionalSpec("message-id", "Message id to delete.")
        ],
        options: [.value("as", "USER", "Moderator identity (default: you).")],
        examples: ["embr mod delete xqc 1234-5678"],
        scopes: ["moderator:manage:chat_messages"],
        mutating: true
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let messageID = try invocation.require(1, "message id")
        let moderatorID = try await context.moderatorID(invocation.value("as"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.deleteMessage(
            broadcasterID: broadcaster.id,
            moderatorID: moderatorID,
            messageID: messageID,
            token: token
        )
        let response = try await context.send(request)
        guard response.status == 204 else {
            throw CLIError.http(status: response.status, body: response.body)
        }
        return CommandResult(MessageActionView(channel: broadcaster.login, messageID: messageID, deleted: true))
    }

    static let automod = CommandSpec(
        ["mod", "automod"],
        summary: "Allow or deny a message AutoMod is holding.",
        positionals: [
            PositionalSpec("channel", "Channel login or id."),
            PositionalSpec("message-id", "Held message id."),
            PositionalSpec("decision", "allow or deny.")
        ],
        options: [.value("as", "USER", "Moderator identity (default: you).")],
        examples: ["embr mod automod xqc 1234-5678 allow"],
        scopes: ["moderator:manage:automod"],
        mutating: true
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let messageID = try invocation.require(1, "message id")
        let decision = try invocation.require(2, "decision").lowercased()
        guard decision == "allow" || decision == "deny" else {
            throw CLIError.usage("The decision must be allow or deny.")
        }
        let moderatorID = try await context.moderatorID(invocation.value("as"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.resolveHeldMessage(
            moderatorID: moderatorID,
            messageID: messageID,
            allow: decision == "allow",
            token: token
        )
        let response = try await context.send(request)
        guard response.status == 204 else {
            throw CLIError.http(status: response.status, body: response.body)
        }
        return CommandResult(AutoModView(channel: broadcaster.login, messageID: messageID, decision: decision))
    }

    static let resolveUnban = CommandSpec(
        ["mod", "resolve-unban"],
        summary: "Approve or deny an unban request.",
        positionals: [
            PositionalSpec("channel", "Channel login or id."),
            PositionalSpec("request-id", "Unban request id."),
            PositionalSpec("decision", "approve or deny.")
        ],
        options: [
            .value("note", "TEXT", "Resolution text shown to the user."),
            .value("as", "USER", "Moderator identity (default: you).")
        ],
        examples: ["embr mod resolve-unban xqc req-1 approve --note \"appealed in chat\""],
        scopes: ["moderator:manage:unban_requests"],
        mutating: true
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let requestID = try invocation.require(1, "request id")
        let decision = try invocation.require(2, "decision").lowercased()
        guard decision == "approve" || decision == "deny" else {
            throw CLIError.usage("The decision must be approve or deny.")
        }
        let moderatorID = try await context.moderatorID(invocation.value("as"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.resolveUnbanRequest(
            broadcasterID: broadcaster.id,
            moderatorID: moderatorID,
            requestID: requestID,
            approve: decision == "approve",
            note: invocation.value("note"),
            token: token
        )
        let response = try await context.send(request)
        guard response.status == 204 else {
            throw CLIError.http(status: response.status, body: response.body)
        }
        return CommandResult(UnbanRequestView(channel: broadcaster.login, requestID: requestID, decision: decision))
    }

    static let moderated = CommandSpec(
        ["mod", "moderated"],
        summary: "Channels a user moderates.",
        positionals: [PositionalSpec("user", "User login or id (default: you).", required: false)],
        examples: ["embr mod moderated --all"],
        scopes: ["user:read:moderated_channels"]
    ) { invocation, context in
        let input: String
        if let named = invocation.optional(0) {
            input = named
        } else {
            input = try await context.login()
        }
        let userID = try await context.resolver.userID(input)
        let factory = try context.factory()
        let token = try context.token()
        var channels: [ModeratedChannel] = []
        var cursor = context.options.after
        var pages = 0
        while true {
            let request = factory.moderatedChannels(userID: userID, after: cursor, token: token)
            let response = try await context.send(request)
            let decoded = StudioHelixDecoder.moderatedChannels(response.body)
            channels.append(contentsOf: decoded.channels)
            cursor = decoded.cursor
            pages += 1
            guard context.options.all, cursor != nil, pages < context.options.maxPages else { break }
            await context.client.sleepIfExhausted(response)
        }
        let views = channels.map(ModeratedChannelView.init)
        let table = CommandSupport.table(
            ["LOGIN", "NAME", "ID"],
            views.map { [$0.login, $0.name, $0.id] }
        )
        return CommandResult(
            views,
            items: views.map { AnyEncodable($0) },
            table: table,
            cursor: cursor,
            count: channels.count
        )
    }

    static let banned = CommandSpec(
        ["mod", "banned"],
        summary: "Banned and timed-out users.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        options: [
            .repeated("user", "USER", "Only these users; repeat for more."),
            .value("as", "USER", "Moderator identity (default: you).")
        ],
        examples: ["embr mod banned xqc --all --json"],
        scopes: ["moderation:read"]
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let userIDs = try await resolveAll(invocation.list("user"), context)
        let factory = try context.factory()
        let token = try context.token()
        let first = invocation.int("first") ?? context.options.first ?? 20
        let request = factory.bannedUsers(broadcasterID: broadcaster.id, userIDs: userIDs, first: first, after: context.options.after, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }
        let (items, cursor) = try await context.collect(request, decode: { try TwitchJSON.decoder.decode(HelixResponse<BannedUser>.self, from: $0) }) { after in
            factory.bannedUsers(broadcasterID: broadcaster.id, userIDs: userIDs, first: first, after: after, token: token)
        }
        let views = items.map(BannedUserView.init)
        let table = CommandSupport.table(
            ["LOGIN", "PERMANENT", "EXPIRES", "REASON", "BY"],
            views.map { [
                $0.userLogin,
                CommandSupport.yesNo($0.permanent),
                CommandSupport.timestamp($0.expiresAt),
                $0.reason ?? "",
                $0.moderatorLogin
            ] }
        )
        return CommandSupport.list(views, table: table, cursor: cursor)
    }

    static let moderators = CommandSpec(
        ["mod", "moderators"],
        summary: "A channel's moderators.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        options: [.repeated("user", "USER", "Only these users; repeat for more.")],
        examples: ["embr mod moderators xqc --all --json"],
        scopes: ["moderation:read"]
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let userIDs = try await resolveAll(invocation.list("user"), context)
        let factory = try context.factory()
        let token = try context.token()
        let first = invocation.int("first") ?? context.options.first ?? 20
        let request = factory.moderators(broadcasterID: broadcaster.id, userIDs: userIDs, first: first, after: context.options.after, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }
        let (items, cursor) = try await context.collect(request, decode: { try TwitchJSON.decoder.decode(HelixResponse<ChannelUser>.self, from: $0) }) { after in
            factory.moderators(broadcasterID: broadcaster.id, userIDs: userIDs, first: first, after: after, token: token)
        }
        let views = items.map(ChannelUserView.init)
        let table = CommandSupport.table(["LOGIN", "NAME", "ID"], views.map { [$0.userLogin, $0.userName, $0.userID] })
        return CommandSupport.list(views, table: table, cursor: cursor)
    }

    static let vips = CommandSpec(
        ["mod", "vips"],
        summary: "A channel's VIPs.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        options: [.repeated("user", "USER", "Only these users; repeat for more.")],
        examples: ["embr mod vips xqc --all --json"],
        scopes: ["channel:read:vips"]
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let userIDs = try await resolveAll(invocation.list("user"), context)
        let factory = try context.factory()
        let token = try context.token()
        let first = invocation.int("first") ?? context.options.first ?? 20
        let request = factory.vips(broadcasterID: broadcaster.id, userIDs: userIDs, first: first, after: context.options.after, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }
        let (items, cursor) = try await context.collect(request, decode: { try TwitchJSON.decoder.decode(HelixResponse<ChannelUser>.self, from: $0) }) { after in
            factory.vips(broadcasterID: broadcaster.id, userIDs: userIDs, first: first, after: after, token: token)
        }
        let views = items.map(ChannelUserView.init)
        let table = CommandSupport.table(["LOGIN", "NAME", "ID"], views.map { [$0.userLogin, $0.userName, $0.userID] })
        return CommandSupport.list(views, table: table, cursor: cursor)
    }

    private static func resolveAll(_ inputs: [String], _ context: RunContext) async throws -> [String] {
        try await context.resolver.users(inputs).map(\.id)
    }
}

private struct BanView: Encodable {
    let channel: String
    let user: String
    let banned: Bool
    let duration: Int?
}

private struct MessageActionView: Encodable {
    let channel: String
    let messageID: String
    let deleted: Bool
}

private struct AutoModView: Encodable {
    let channel: String
    let messageID: String
    let decision: String
}

private struct UnbanRequestView: Encodable {
    let channel: String
    let requestID: String
    let decision: String
}

private struct ModeratedChannelView: Encodable {
    let id: String
    let login: String
    let name: String

    init(_ channel: ModeratedChannel) {
        id = channel.id
        login = channel.login
        name = channel.name
    }
}
