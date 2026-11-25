import Foundation
import EmbrCore

enum EmoteCommands {
    static let specs: [CommandSpec] = [
        twitch,
        sevenTV,
        bttv,
        ffz,
        all
    ]

    static let twitch = CommandSpec(
        ["emotes", "twitch"],
        summary: "Twitch global or channel emotes.",
        positionals: [PositionalSpec("channel", "Channel login or id; omit for global emotes.", required: false)],
        examples: ["embr emotes twitch", "embr emotes twitch xqc"],
        scopes: ["any app or user token"]
    ) { invocation, context in
        let factory = try context.factory()
        let token = try context.token()
        let request: HTTPRequest
        if let channel = invocation.optional(0) {
            let broadcaster = try await context.resolver.user(channel)
            request = factory.channelEmotes(broadcasterID: broadcaster.id, token: token)
        } else {
            request = factory.globalEmotes(token: token)
        }
        let response = try await context.send(request)
        let page = try HelixDecoder.emotes(response.body)
        let views = page.data.map(EmoteView.init)
        let table = CommandSupport.table(
            ["PROVIDER", "NAME", "ID", "ANIMATED"],
            views.map { ["Twitch", $0.name, $0.id, CommandSupport.yesNo($0.animated)] }
        )
        return CommandSupport.list(views, table: table, cursor: page.pagination?.cursor)
    }

    static let sevenTV = providerSpec(path: ["emotes", "7tv"], name: "7TV", provider: .sevenTV)
    static let bttv = providerSpec(path: ["emotes", "bttv"], name: "BetterTTV", provider: .betterTTV)
    static let ffz = providerSpec(path: ["emotes", "ffz"], name: "FrankerFaceZ", provider: .frankerFaceZ)

    static let all = CommandSpec(
        ["emotes", "all"],
        summary: "Every emote for a channel: Twitch, 7TV, BetterTTV and FrankerFaceZ.",
        positionals: [PositionalSpec("channel", "Channel login or id.")],
        examples: ["embr emotes all xqc --json"],
        scopes: ["any app or user token"]
    ) { invocation, context in
        let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
        let factory = try context.factory()
        let token = try context.token()
        async let twitchEmotes = try? fetchTwitch(broadcaster.id, factory: factory, token: token, context: context)
        async let sevenTVEmotes = try? fetchProvider(.sevenTV, broadcaster.id, context)
        async let bttvEmotes = try? fetchProvider(.betterTTV, broadcaster.id, context)
        async let ffzEmotes = try? fetchProvider(.frankerFaceZ, broadcaster.id, context)
        let (twitch, sevenTV, bttv, ffz) = await (twitchEmotes, sevenTVEmotes, bttvEmotes, ffzEmotes)
        var combined: [ProviderEmote] = []
        if let twitch {
            combined += twitch
        } else {
            context.renderer.note("Twitch emotes failed; continuing with the third-party providers.")
        }
        if let sevenTV { combined += sevenTV } else { context.renderer.note("7TV emotes failed; continuing.") }
        if let bttv { combined += bttv } else { context.renderer.note("BetterTTV emotes failed; continuing.") }
        if let ffz { combined += ffz } else { context.renderer.note("FrankerFaceZ emotes failed; continuing.") }
        let table = CommandSupport.table(
            ["PROVIDER", "NAME", "ID"],
            combined.map { [$0.providerName, $0.name, $0.id] }
        )
        return CommandSupport.list(combined, table: table, cursor: nil)
    }

    private static func providerSpec(
        path: [String],
        name: String,
        provider: EmoteProvider
    ) -> CommandSpec {
        CommandSpec(
            path,
            summary: "\(name) emotes for a channel.",
            positionals: [PositionalSpec("channel", "Channel login or id.")],
            examples: ["embr \(path.joined(separator: " ")) xqc --json"],
            scopes: ["any app or user token"]
        ) { invocation, context in
            let broadcaster = try await context.resolver.user(try invocation.require(0, "channel"))
            let emotes = try await fetchProvider(provider, broadcaster.id, context)
            let table = CommandSupport.table(
                ["PROVIDER", "NAME", "ID"],
                emotes.map { [$0.providerName, $0.name, $0.id] }
            )
            return CommandSupport.list(emotes, table: table, cursor: nil)
        }
    }

    static func fetchProvider(_ provider: EmoteProvider, _ broadcasterID: String, _ context: RunContext) async throws -> [ProviderEmote] {
        switch provider {
        case .sevenTV:
            let url = URL(string: "https://7tv.io/v3/users/twitch/\(broadcasterID)")!
            let response = try await context.send(HTTPRequest(method: .get, url: url))
            let user = try context.decode(SevenTVUser.self, response)
            return (user.emoteSet?.emotes ?? []).map { emote in
                let animated = emote.data?.animated ?? false
                var images: [String: String] = [:]
                for scale in ["1x", "2x", "4x"] {
                    images[scale] = "https://cdn.7tv.app/emote/\(emote.id)/\(scale).webp"
                }
                return ProviderEmote(provider: "7tv", providerName: "7TV", id: emote.id, name: emote.name, animated: animated, images: images)
            }
        case .betterTTV:
            let url = URL(string: "https://api.betterttv.net/3/cached/users/twitch/\(broadcasterID)")!
            let response = try await context.send(HTTPRequest(method: .get, url: url))
            let user = try context.decode(BTTVUser.self, response)
            return (user.channelEmotes + user.sharedEmotes).map { emote in
                var images: [String: String] = [:]
                for scale in ["1x", "2x", "3x"] {
                    images[scale] = "https://cdn.betterttv.net/emote/\(emote.id)/\(scale)"
                }
                return ProviderEmote(provider: "bttv", providerName: "BetterTTV", id: emote.id, name: emote.code, animated: emote.imageType == "gif", images: images)
            }
        case .frankerFaceZ:
            let url = URL(string: "https://api.frankerfacez.com/v1/room/id/\(broadcasterID)")!
            let response = try await context.send(HTTPRequest(method: .get, url: url))
            let room = try context.decode(FFZRoom.self, response)
            return room.sets.values.flatMap(\.emoticons).map { emote in
                var images: [String: String] = [:]
                for (scale, value) in emote.urls {
                    images[scale] = value
                }
                return ProviderEmote(
                    provider: "ffz",
                    providerName: "FrankerFaceZ",
                    id: String(emote.id),
                    name: emote.name,
                    animated: emote.animated ?? false,
                    images: images
                )
            }
        case .twitch:
            return []
        }
    }

    private static func fetchTwitch(
        _ broadcasterID: String,
        factory: HelixRequestFactory,
        token: String,
        context: RunContext
    ) async throws -> [ProviderEmote] {
        let request = factory.channelEmotes(broadcasterID: broadcasterID, token: token)
        let response = try await context.send(request)
        let page = try HelixDecoder.emotes(response.body)
        return page.data.map { emote in
            var images: [String: String] = [:]
            for (scale, url) in emote.images.urlsByScale {
                images["\(scale.rawValue)x"] = url.absoluteString
            }
            return ProviderEmote(
                provider: "twitch",
                providerName: "Twitch",
                id: emote.id,
                name: emote.name,
                animated: emote.isAnimated,
                images: images
            )
        }
    }
}

struct ProviderEmote: Encodable {
    let provider: String
    let providerName: String
    let id: String
    let name: String
    let animated: Bool
    let images: [String: String]
}

private struct SevenTVUser: Decodable {
    let emoteSet: EmoteSet?

    struct EmoteSet: Decodable {
        let emotes: [Emote]
    }

    struct Emote: Decodable {
        let id: String
        let name: String
        let data: Data?

        struct Data: Decodable {
            let animated: Bool?
        }
    }

    enum CodingKeys: String, CodingKey {
        case emoteSet = "emote_set"
    }
}

private struct BTTVUser: Decodable {
    let channelEmotes: [Emote]
    let sharedEmotes: [Emote]

    struct Emote: Decodable {
        let id: String
        let code: String
        let imageType: String?
    }

    enum CodingKeys: String, CodingKey {
        case channelEmotes
        case sharedEmotes
    }
}

private struct FFZRoom: Decodable {
    let sets: [String: Set]

    struct Set: Decodable {
        let emoticons: [Emote]
    }

    struct Emote: Decodable {
        let id: Int
        let name: String
        let animated: Bool?
        let urls: [String: String]
    }
}
