#if DEBUG
import Foundation
import EmbrCore

/// The invented emote world: Twitch's globals and each channel's own, plus a 7TV, a BetterTTV and a FrankerFaceZ set,
/// served the way each service answers so the emote keyboard and chat show every provider. Every emote is drawn by
/// `DemoArt` from its name; none is a real emote.
enum DemoEmotes {
    /// What an emote is drawn from: a glyph, or a word set in bold for emotes that are text.
    struct Look: Sendable {
        let glyph: String
        let isWord: Bool
        let tint: UInt32
    }

    static let twitchGlobal = ["pogfox", "heartbeat", "clapfox", "sadmoth", "owlwave", "noodlelove", "gg", "hypefox", "o7", "cozycup", "kekw2", "popcornpanda"]
    static let sevenTV = ["frogvibe", "catbop", "duckdance", "brainmelt", "zoomies", "nodnod", "ghosty", "sparkle"]
    static let betterTTV = ["teatime", "bonk", "crowned", "rocketgo", "shrugcat", "pizzatime"]
    static let frankerFaceZ = ["dogwave", "thinkhard", "salute", "partyhat", "bigeyes"]
    private static let channelSuffixes = ["Hype", "Love", "Wave", "Win", "Cozy", "GG"]

    private static let looks: [String: Look] = [
        "pogfox": Look(glyph: "🦊", isWord: false, tint: 0xFF8A3D),
        "heartbeat": Look(glyph: "💜", isWord: false, tint: 0x9147FF),
        "clapfox": Look(glyph: "👏", isWord: false, tint: 0xFFC857),
        "sadmoth": Look(glyph: "🥲", isWord: false, tint: 0x8AB4FF),
        "owlwave": Look(glyph: "🦉", isWord: false, tint: 0xB0895E),
        "noodlelove": Look(glyph: "🍜", isWord: false, tint: 0xFF6B8B),
        "gg": Look(glyph: "GG", isWord: true, tint: 0x2FB344),
        "hypefox": Look(glyph: "🔥", isWord: false, tint: 0xFF4D4D),
        "o7": Look(glyph: "🫡", isWord: false, tint: 0xFFD23F),
        "cozycup": Look(glyph: "☕️", isWord: false, tint: 0xC08457),
        "kekw2": Look(glyph: "😂", isWord: false, tint: 0xFFD23F),
        "popcornpanda": Look(glyph: "🍿", isWord: false, tint: 0xFF4D4D),
        "frogvibe": Look(glyph: "🐸", isWord: false, tint: 0x7EE787),
        "catbop": Look(glyph: "🐱", isWord: false, tint: 0xFFB454),
        "duckdance": Look(glyph: "🦆", isWord: false, tint: 0x9ACD32),
        "brainmelt": Look(glyph: "🫠", isWord: false, tint: 0xFFD23F),
        "zoomies": Look(glyph: "💨", isWord: false, tint: 0x6BD6FF),
        "nodnod": Look(glyph: "🙂‍↕️", isWord: false, tint: 0xFFD23F),
        "ghosty": Look(glyph: "👻", isWord: false, tint: 0xE6E6F0),
        "sparkle": Look(glyph: "✨", isWord: false, tint: 0xFFD23F),
        "teatime": Look(glyph: "🍵", isWord: false, tint: 0x7EE787),
        "bonk": Look(glyph: "🔨", isWord: false, tint: 0xB0B0B8),
        "crowned": Look(glyph: "👑", isWord: false, tint: 0xFFC857),
        "rocketgo": Look(glyph: "🚀", isWord: false, tint: 0x5AA9FF),
        "shrugcat": Look(glyph: "😼", isWord: false, tint: 0xFFB454),
        "pizzatime": Look(glyph: "🍕", isWord: false, tint: 0xFF8A3D),
        "dogwave": Look(glyph: "🐶", isWord: false, tint: 0xC08457),
        "thinkhard": Look(glyph: "🤔", isWord: false, tint: 0xFFD23F),
        "salute": Look(glyph: "🫡", isWord: false, tint: 0xFFD23F),
        "partyhat": Look(glyph: "🥳", isWord: false, tint: 0xFF7AC6),
        "bigeyes": Look(glyph: "🥺", isWord: false, tint: 0xFFD23F),
    ]

    private static let suffixLooks: [String: Look] = [
        "Hype": Look(glyph: "🔥", isWord: false, tint: 0xFF4D4D),
        "Love": Look(glyph: "💖", isWord: false, tint: 0xFF6B8B),
        "Wave": Look(glyph: "👋", isWord: false, tint: 0xFFC857),
        "Win": Look(glyph: "🏆", isWord: false, tint: 0xFFC857),
        "Cozy": Look(glyph: "🧸", isWord: false, tint: 0xC08457),
        "GG": Look(glyph: "GG", isWord: true, tint: 0x9147FF),
    ]

    /// How an emote is drawn, or nil for a name the demo does not know.
    static func look(for name: String) -> Look? {
        if let look = looks[name] { return look }
        return channelSuffixes.first { name.hasSuffix($0) && name.count > $0.count }.flatMap { suffixLooks[$0] }
    }

    /// A channel's own Twitch emotes, prefixed with the first letters of its login as Twitch's are.
    static func channelNames(login: String) -> [String] {
        let prefix = String(login.prefix(5)).lowercased()
        return channelSuffixes.map { prefix + $0 }
    }

    /// Every name a chat line may use, so the scripted chat shows emotes from each provider.
    static func chatNames(login: String) -> [String] {
        twitchGlobal + sevenTV + betterTTV + frankerFaceZ + channelNames(login: login)
    }

    private static func imageURL(_ name: String, scale: String) -> String {
        "https://\(DemoWorld.host)/emote/\(name)/\(scale)"
    }

    /// Helix's emote listing, Twitch's globals or one channel's own.
    static func twitch(channelID: String?) -> [[String: Any]] {
        let login = channelID.flatMap { id in DemoWorld.channels.first { $0.id == id }?.login }
        let names = login.map(channelNames(login:)) ?? twitchGlobal
        return names.map { name in
            [
                "id": "demo-\(name)",
                "name": name,
                "images": ["url_1x": imageURL(name, scale: "1"), "url_2x": imageURL(name, scale: "2"), "url_4x": imageURL(name, scale: "4")],
                "format": ["static"],
                "scale": ["1.0", "2.0", "3.0"],
                "theme_mode": ["dark"],
                "emote_type": login == nil ? "globals" : "subscriptions"
            ]
        }
    }

    /// 7TV, BetterTTV and FrankerFaceZ answered offline: each provider's set at its global route and an empty set at its
    /// channel route, so every provider gets one section in the emote keyboard.
    static func thirdParty(_ url: URL) -> Any? {
        let path = url.path
        switch url.host {
        case "7tv.io":
            if path == "/v3/emote-sets/global" { return ["id": "demo-global", "emotes": sevenTV.map(sevenTVEntry)] }
            if path.hasPrefix("/v3/users/twitch/") { return ["emote_set": ["id": "demo-channel", "emotes": [Any]()]] }
        case "api.betterttv.net":
            if path == "/3/cached/emotes/global" { return betterTTV.map { ["id": $0, "code": $0, "imageType": "png", "animated": false] } }
            if path.hasPrefix("/3/cached/users/twitch/") { return ["channelEmotes": [Any](), "sharedEmotes": [Any]()] }
        case "api.frankerfacez.com":
            if path == "/v1/set/global" { return ["default_sets": [3], "sets": ["3": ["emoticons": frankerFaceZ.enumerated().map(frankerFaceZEntry)]]] }
            if path.hasPrefix("/v1/room/id/") { return ["room": ["set": 100], "sets": ["100": ["emoticons": [Any]()]]] }
        default:
            break
        }
        return nil
    }

    private static func sevenTVEntry(_ name: String) -> [String: Any] {
        let files = ["1x", "2x", "4x"].enumerated().map { index, scale -> [String: Any] in
            let side = 32 << index
            return ["name": "\(scale).webp", "format": "WEBP", "width": side, "height": side, "frame_count": 1]
        }
        return ["id": name, "name": name, "flags": 0, "data": ["animated": false, "host": ["url": "//\(DemoWorld.host)/emote/\(name)", "files": files]]]
    }

    private static func frankerFaceZEntry(_ index: Int, _ name: String) -> [String: Any] {
        let urls = ["1": "//\(DemoWorld.host)/emote/\(name)/1", "2": "//\(DemoWorld.host)/emote/\(name)/2", "4": "//\(DemoWorld.host)/emote/\(name)/4"]
        return ["id": 500 + index, "name": name, "width": 32, "height": 32, "urls": urls]
    }
}
#endif
