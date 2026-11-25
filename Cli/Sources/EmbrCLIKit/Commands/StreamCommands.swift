import Foundation
import EmbrCore

enum StreamCommands {
    static let specs: [CommandSpec] = [
        streamsTop,
        streamsGame,
        streamsFollowed,
        streamsGet,
        gamesTop,
        searchCategories,
        searchChannels
    ]

    static let streamsTop = CommandSpec(
        ["streams", "top"],
        summary: "Live streams by viewer count.",
        examples: ["embr streams top --first 10"],
        scopes: ["any app or user token"]
    ) { invocation, context in
        let factory = try context.factory()
        let token = try context.token()
        let first = invocation.int("first") ?? context.options.first ?? 20
        let request = factory.topStreams(first: first, after: context.options.after, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }
        let (items, cursor) = try await context.collect(request, decode: HelixDecoder.streams) { after in
            factory.topStreams(first: first, after: after, token: token)
        }
        return CommandSupport.list(items, table: streamTable(items), cursor: cursor)
    }

    static let streamsGame = CommandSpec(
        ["streams", "game"],
        summary: "Live streams for one category id.",
        positionals: [PositionalSpec("game-id", "Twitch category id (see `embr search categories`).")],
        examples: ["embr streams game 509658 --first 10"],
        scopes: ["any app or user token"]
    ) { invocation, context in
        let gameID = try invocation.require(0, "game id")
        let factory = try context.factory()
        let token = try context.token()
        let first = invocation.int("first") ?? context.options.first ?? 20
        let request = factory.streamsByGame(gameID: gameID, first: first, after: context.options.after, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }
        let (items, cursor) = try await context.collect(request, decode: HelixDecoder.streams) { after in
            factory.streamsByGame(gameID: gameID, first: first, after: after, token: token)
        }
        return CommandSupport.list(items, table: streamTable(items), cursor: cursor)
    }

    static let streamsFollowed = CommandSpec(
        ["streams", "followed"],
        summary: "Live streams from the signed-in user's follows.",
        positionals: [PositionalSpec("user", "User to read follows for (default: you).", required: false)],
        examples: ["embr streams followed --first 20"],
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
        let request = factory.followedStreams(userID: userID, first: first, after: context.options.after, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }
        let (items, cursor) = try await context.collect(request, decode: HelixDecoder.streams) { after in
            factory.followedStreams(userID: userID, first: first, after: after, token: token)
        }
        return CommandSupport.list(items, table: streamTable(items), cursor: cursor)
    }

    static let streamsGet = CommandSpec(
        ["streams", "get"],
        summary: "Live stream status for specific channels.",
        positionals: [PositionalSpec("channel", "One or more logins or ids.", variadic: true)],
        examples: ["embr streams get xqc shroud --json"],
        scopes: ["any app or user token"]
    ) { invocation, context in
        guard !invocation.positionals.isEmpty else {
            throw CLIError.usage("Name at least one channel.")
        }
        let users = try await context.resolver.users(invocation.positionals)
        let ids = users.map(\.id)
        let factory = try context.factory()
        let token = try context.token()
        let request = factory.streamsByUserIDs(ids, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }
        let response = try await context.send(request)
        let page: HelixResponse<LiveStream>
        do {
            page = try HelixDecoder.streams(response.body)
        } catch {
            throw CLIError(.decode, "Could not decode the stream lookup: \(error)")
        }
        let byLogin = Dictionary(uniqueKeysWithValues: page.data.map { ($0.userLogin.lowercased(), $0) })
        let ordered = users.compactMap { byLogin[$0.login.lowercased()] }
        return CommandSupport.list(ordered, table: streamTable(ordered), cursor: nil)
    }

    static let gamesTop = CommandSpec(
        ["games", "top"],
        summary: "Categories with the most viewers.",
        examples: ["embr games top --first 20"],
        scopes: ["any app or user token"]
    ) { invocation, context in
        let factory = try context.factory()
        let token = try context.token()
        let first = invocation.int("first") ?? context.options.first ?? 20
        let request = factory.topGames(first: first, after: context.options.after, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }
        let (items, cursor) = try await context.collect(request, decode: HelixDecoder.games) { after in
            factory.topGames(first: first, after: after, token: token)
        }
        let table = CommandSupport.table(
            ["ID", "NAME"],
            items.map { [$0.id, $0.name] }
        )
        return CommandSupport.list(items, table: table, cursor: cursor)
    }

    static let searchCategories = CommandSpec(
        ["search", "categories"],
        summary: "Search Twitch categories by name.",
        positionals: [PositionalSpec("query", "What to search for.")],
        examples: ["embr search categories \"just chatting\""],
        scopes: ["any app or user token"]
    ) { invocation, context in
        let query = try invocation.require(0, "query")
        let factory = try context.factory()
        let token = try context.token()
        let first = invocation.int("first") ?? context.options.first ?? 20
        let request = factory.searchCategories(query: query, first: first, after: context.options.after, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }
        let (items, cursor) = try await context.collect(request, decode: HelixDecoder.games) { after in
            factory.searchCategories(query: query, first: first, after: after, token: token)
        }
        let table = CommandSupport.table(["ID", "NAME"], items.map { [$0.id, $0.name] })
        return CommandSupport.list(items, table: table, cursor: cursor)
    }

    static let searchChannels = CommandSpec(
        ["search", "channels"],
        summary: "Search channels by name.",
        positionals: [PositionalSpec("query", "What to search for.")],
        options: [.flag("live", "Only channels that are live.")],
        examples: ["embr search channels shroud --live"],
        scopes: ["any app or user token"]
    ) { invocation, context in
        let query = try invocation.require(0, "query")
        let factory = try context.factory()
        let token = try context.token()
        let first = invocation.int("first") ?? context.options.first ?? 20
        let liveOnly = invocation.has("live")
        let request = factory.searchChannels(query: query, liveOnly: liveOnly, first: first, after: context.options.after, token: token)
        if let raw = try await CommandSupport.raw(request, context) { return raw }
        let (items, cursor) = try await context.collect(request, decode: HelixDecoder.channelSearch) { after in
            factory.searchChannels(query: query, liveOnly: liveOnly, first: first, after: after, token: token)
        }
        let table = CommandSupport.table(
            ["LOGIN", "LIVE", "GAME", "TITLE"],
            items.map { [$0.broadcasterLogin, CommandSupport.yesNo($0.isLive), $0.gameName, $0.title] }
        )
        return CommandSupport.list(items, table: table, cursor: cursor)
    }

    private static func streamTable(_ streams: [LiveStream]) -> TableData {
        CommandSupport.table(
            ["LOGIN", "VIEWERS", "GAME", "TITLE"],
            streams.map { [$0.userLogin, String($0.viewerCount), $0.gameName, $0.title] }
        )
    }
}
