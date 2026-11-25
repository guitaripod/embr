import Foundation
import EmbrCore

enum DirectoryCommands {
    static let specs: [CommandSpec] = [
        usersGet,
        channelsInfo,
        channelsEdit,
        channelsFollowers,
        channelsFollowed,
        videosList,
        clipsList,
        scheduleGet
    ]

    static let usersGet = CommandSpec(
        ["users", "get"],
        summary: "Look up Twitch users by login or id.",
        positionals: [PositionalSpec("user", "One or more logins or numeric ids.", variadic: true)],
        examples: ["embr users get xqc 12345 --json"],
        scopes: ["any app or user token"]
    ) { invocation, context in
        guard !invocation.positionals.isEmpty else {
            throw CLIError.usage("Name at least one user.")
        }
        let inputs = invocation.positionals
        let ids = inputs.filter { $0.allSatisfy(\.isNumber) && !$0.isEmpty }
        let logins = inputs.filter { !($0.allSatisfy(\.isNumber) && !$0.isEmpty) }
        let factory = try context.factory()
        let token = try context.token()
        var users: [TwitchUser] = []
        var seen = Set<String>()

        if !ids.isEmpty {
            let request = factory.usersByIDs(ids, token: token)
            if let raw = try await CommandSupport.raw(request, context) { return raw }
            let response = try await context.send(request)
            for user in try HelixDecoder.users(response.body).data where seen.insert(user.id).inserted {
                users.append(user)
            }
        }
        if !logins.isEmpty {
            let request = factory.usersByLogins(logins, token: token)
            let response = try await context.send(request)
            for user in try HelixDecoder.users(response.body).data where seen.insert(user.id).inserted {
                users.append(user)
            }
        }
        let table = CommandSupport.table(
            ["LOGIN", "NAME", "ID", "TYPE"],
            users.map { [$0.login, $0.displayName, $0.id, $0.broadcasterType] }
        )
        return CommandSupport.list(users, table: table, cursor: nil)
    }

    static let channelsInfo = CommandSpec(
        ["channels", "info"],
        summary: "Title, category, language and tags for a channel.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        examples: ["embr channels info xqc"],
        scopes: ["any app or user token"]
    ) { invocation, context in
        let user = try await context.resolver.user(try invocation.require(0, "channel"))
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.channelInformation(broadcasterID: user.id, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }
        let response = try await context.send(request)
        let page = try HelixDecoder.channelInfo(response.body)
        guard let channel = page.data.first else {
            throw CLIError.notFound("Twitch has no channel information for \(user.login).")
        }
        return CommandResult(channel, count: 1)
    }

    static let channelsEdit = CommandSpec(
        ["channels", "edit"],
        summary: "Change a channel's title, category, language, delay, tags or content labels.",
        positionals: [PositionalSpec("channel", "Channel login or id; must be the token's own channel.")],
        options: [
            .value("title", "TEXT", "Stream title."),
            .value("game-id", "ID", "Category id; use 0 to unset."),
            .value("language", "CODE", "ISO 639-1 language code."),
            .value("delay", "SECONDS", "Partner-only broadcast delay."),
            .repeated("tag", "TAG", "Channel tag; repeat for more."),
            .flag("clear-tags", "Remove every channel tag."),
            .repeated("ccl", "ID=on|off", "Content classification label, e.g. Gambling=on."),
            .value("branded", "on|off", "Whether the channel has branded content.")
        ],
        examples: [
            "embr channels edit xqc --title \"Late night\" --game-id 509658",
            "embr channels edit xqc --ccl Gambling=on --tag English"
        ],
        scopes: ["channel:manage:broadcast"],
        mutating: true
    ) { invocation, context in
        let user = try await context.resolver.user(try invocation.require(0, "channel"))
        let names = ["title", "game-id", "language", "delay", "tag", "clear-tags", "ccl", "branded"]
        try CommandSupport.requireAnyFlag(invocation, names)

        var tags: [String]? = invocation.list("tag").isEmpty ? nil : invocation.list("tag")
        if invocation.has("clear-tags") { tags = [] }
        let labels = try invocation.list("ccl").map { raw -> ContentClassificationLabel in
            let parts = raw.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                throw CLIError.usage("`--ccl` takes ID=on|off, got `\(raw)`.")
            }
            let enabled: Bool
            switch parts[1].lowercased() {
            case "on", "true", "1": enabled = true
            case "off", "false", "0": enabled = false
            default: throw CLIError.usage("`--ccl` takes on or off, got `\(parts[1])`.")
            }
            return ContentClassificationLabel(id: parts[0], isEnabled: enabled)
        }
        let branded = try invocation.value("branded").map { try CommandSupport.onOff($0, "branded") }
        let update = ChannelUpdate(
            gameID: invocation.value("game-id"),
            language: invocation.value("language"),
            title: invocation.value("title"),
            delay: invocation.int("delay"),
            tags: tags,
            contentClassificationLabels: labels.isEmpty ? nil : labels,
            isBrandedContent: branded
        )
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.modifyChannel(broadcasterID: user.id, update: update, token: token)
        let response = try await context.send(request)
        guard response.status == 204 else {
            throw CLIError.http(status: response.status, body: response.body)
        }
        let changed = names.filter { name in
            switch name {
            case "tag": return invocation.list("tag").count > 0
            case "ccl": return !invocation.list("ccl").isEmpty
            default: return invocation.value(name) != nil
            }
        }
        return CommandResult(ChannelEditView(broadcasterID: user.id, login: user.login, changed: changed))
    }

    static let channelsFollowers = CommandSpec(
        ["channels", "followers"],
        summary: "Followers of a channel, newest first.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        examples: ["embr channels followers xqc --first 20"],
        scopes: ["moderator:read:followers"]
    ) { invocation, context in
        let user = try await context.resolver.user(try invocation.require(0, "channel"))
        let factory = try context.factory()
        let token = try context.token()
        let first = invocation.int("first") ?? context.options.first ?? 20
        let request = factory.channelFollowers(broadcasterID: user.id, first: first, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }
        let response = try await context.send(request)
        let decoded = StudioHelixDecoder.followers(response.body)
        let table = CommandSupport.table(
            ["USER", "ID", "FOLLOWED"],
            decoded.recent.map { [$0.userName, $0.userID, CommandSupport.timestamp($0.followedAt)] }
        )
        return CommandResult(
            FollowersView(total: decoded.total, followers: decoded.recent),
            items: decoded.recent.map { AnyEncodable($0) },
            table: table,
            total: decoded.total,
            count: decoded.recent.count
        )
    }

    static let channelsFollowed = CommandSpec(
        ["channels", "followed"],
        summary: "Channels a user follows.",
        positionals: [PositionalSpec("user", "User login or id (default: you).", required: false)],
        examples: ["embr channels followed --first 50"],
        scopes: ["user:read:follows"]
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
        let first = invocation.int("first") ?? context.options.first ?? 100
        let request = factory.followedChannels(userID: userID, first: first, after: context.options.after, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }
        let (items, cursor) = try await context.collect(request, decode: HelixDecoder.followedChannels) { after in
            factory.followedChannels(userID: userID, first: first, after: after, token: token)
        }
        let table = CommandSupport.table(
            ["LOGIN", "NAME", "FOLLOWED"],
            items.map { [$0.broadcasterLogin, $0.broadcasterName, CommandSupport.timestamp($0.followedAt)] }
        )
        return CommandSupport.list(items, table: table, cursor: cursor)
    }

    static let videosList = CommandSpec(
        ["videos", "list"],
        summary: "Videos and past broadcasts for a user.",
        positionals: [PositionalSpec("user", "User login or id (default: you).", required: false)],
        examples: ["embr videos list xqc --first 10"],
        scopes: ["any app or user token"]
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
        let first = invocation.int("first") ?? context.options.first ?? 20
        let request = factory.videos(userID: userID, first: first, after: context.options.after, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }
        let (items, cursor) = try await context.collect(request, decode: HelixDecoder.videos) { after in
            factory.videos(userID: userID, first: first, after: after, token: token)
        }
        let table = CommandSupport.table(
            ["ID", "TITLE", "TYPE", "VIEWS", "DURATION"],
            items.map { [$0.id, $0.title, $0.type, String($0.viewCount), "\($0.durationSeconds)s"] }
        )
        return CommandSupport.list(items, table: table, cursor: cursor)
    }

    static let clipsList = CommandSpec(
        ["clips", "list"],
        summary: "Clips from a channel.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        examples: ["embr clips list xqc --first 10"],
        scopes: ["any app or user token"]
    ) { invocation, context in
        let user = try await context.resolver.user(try invocation.require(0, "channel"))
        let factory = try context.factory()
        let token = try context.token()
        let first = invocation.int("first") ?? context.options.first ?? 20
        let request = factory.clips(broadcasterID: user.id, first: first, after: context.options.after, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }
        let (items, cursor) = try await context.collect(request, decode: HelixDecoder.clips) { after in
            factory.clips(broadcasterID: user.id, first: first, after: after, token: token)
        }
        let table = CommandSupport.table(
            ["ID", "TITLE", "CREATOR", "VIEWS", "SECONDS"],
            items.map { [$0.id, $0.title, $0.creatorName, String($0.viewCount), String(Int($0.duration))] }
        )
        return CommandSupport.list(items, table: table, cursor: cursor)
    }

    static let scheduleGet = CommandSpec(
        ["schedule", "get"],
        summary: "A channel's streaming schedule and vacation window.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        examples: ["embr schedule get xqc --first 10"],
        scopes: ["any app or user token"]
    ) { invocation, context in
        let user = try await context.resolver.user(try invocation.require(0, "channel"))
        let factory = try context.factory()
        let token = try context.token()
        let first = invocation.int("first") ?? context.options.first ?? 25
        let request = factory.schedule(broadcasterID: user.id, first: first, after: context.options.after, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }

        var segments: [ScheduleSegment] = []
        var cursor = context.options.after
        var pageCount = 0
        var firstPage: SchedulePage?
        while true {
            let current = pageCount == 0 ? request : factory.schedule(broadcasterID: user.id, first: first, after: cursor, token: token)
            let response = try await context.send(current)
            let page = try HelixDecoder.schedule(response.body)
            if firstPage == nil { firstPage = page }
            segments.append(contentsOf: page.segments)
            cursor = page.cursor
            pageCount += 1
            guard context.options.all, cursor != nil, pageCount < context.options.maxPages else { break }
            await context.client.sleepIfExhausted(response)
        }
        let table = CommandSupport.table(
            ["START", "END", "TITLE", "CATEGORY"],
            segments.map { [
                CommandSupport.timestamp($0.startTime),
                CommandSupport.timestamp($0.endTime),
                $0.title,
                $0.categoryName ?? ""
            ] }
        )
        return CommandResult(
            ScheduleView(
                broadcasterLogin: firstPage?.broadcasterLogin,
                broadcasterName: firstPage?.broadcasterName,
                vacation: firstPage?.vacation,
                segments: segments
            ),
            items: segments.map { AnyEncodable($0) },
            table: table,
            cursor: cursor,
            count: segments.count
        )
    }
}

private struct ChannelEditView: Encodable {
    let broadcasterID: String
    let login: String
    let changed: [String]
}

private struct FollowersView: Encodable {
    let total: Int
    let followers: [StudioFollow]
}

private struct ScheduleView: Encodable {
    let broadcasterLogin: String?
    let broadcasterName: String?
    let vacation: DateInterval?
    let segments: [ScheduleSegment]
}
