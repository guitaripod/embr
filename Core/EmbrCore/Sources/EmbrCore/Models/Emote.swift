import Foundation

public enum EmoteProvider: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case twitch
    case sevenTV
    case betterTTV
    case frankerFaceZ

    public var displayName: String {
        switch self {
        case .twitch: return "Twitch"
        case .sevenTV: return "7TV"
        case .betterTTV: return "BetterTTV"
        case .frankerFaceZ: return "FrankerFaceZ"
        }
    }

    /// Lower wins when two providers define the same emote name. Channel emotes always shadow globals regardless.
    public var precedence: Int {
        switch self {
        case .twitch: return 0
        case .sevenTV: return 1
        case .betterTTV: return 2
        case .frankerFaceZ: return 3
        }
    }
}

public enum EmoteScale: Int, Sendable, Equatable, Hashable, Codable, CaseIterable, Comparable {
    case x1 = 1
    case x2 = 2
    case x3 = 3
    case x4 = 4

    public static func < (lhs: EmoteScale, rhs: EmoteScale) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum EmoteFormat: String, Sendable, Equatable, Hashable, Codable {
    case `static`
    case animated
}

public struct EmoteImageSet: Sendable, Equatable, Hashable {
    public let urlsByScale: [EmoteScale: URL]

    public init(urlsByScale: [EmoteScale: URL]) {
        self.urlsByScale = urlsByScale
    }

    public func url(preferring scale: EmoteScale) -> URL? {
        if let exact = urlsByScale[scale] { return exact }
        let available = urlsByScale.keys.sorted()
        guard !available.isEmpty else { return nil }
        let larger = available.first(where: { $0 > scale })
        return urlsByScale[larger ?? available.last!]
    }
}

public struct Emote: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let provider: EmoteProvider
    public let images: EmoteImageSet
    public let isAnimated: Bool
    public let isZeroWidth: Bool
    public let aspectRatio: Double
    public let ownerID: String?

    public init(
        id: String,
        name: String,
        provider: EmoteProvider,
        images: EmoteImageSet,
        isAnimated: Bool = false,
        isZeroWidth: Bool = false,
        aspectRatio: Double = 1.0,
        ownerID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.images = images
        self.isAnimated = isAnimated
        self.isZeroWidth = isZeroWidth
        self.aspectRatio = aspectRatio
        self.ownerID = ownerID
    }
}

public enum EmoteCDN {
    public static func twitchURL(id: String, format: EmoteFormat, scale: EmoteScale, theme: String = "dark") -> URL? {
        let formatPath = format == .animated ? "animated" : "static"
        return URL(string: "https://static-cdn.jtvnw.net/emoticons/v2/\(id)/\(formatPath)/\(theme)/\(scale.rawValue).0")
    }

    public static func twitchEmote(from ref: TwitchEmoteRef) -> Emote {
        let isAnimated = ref.formats.contains(.animated)
        let format: EmoteFormat = isAnimated ? .animated : .static
        var urls: [EmoteScale: URL] = [:]
        for scale in EmoteScale.allCases {
            if let url = twitchURL(id: ref.id, format: format, scale: scale) {
                urls[scale] = url
            }
        }
        return Emote(
            id: ref.id,
            name: ref.text,
            provider: .twitch,
            images: EmoteImageSet(urlsByScale: urls),
            isAnimated: isAnimated,
            isZeroWidth: false,
            ownerID: ref.ownerID
        )
    }
}

public struct EmoteCatalog: Sendable, Equatable {
    public private(set) var global: [String: Emote]
    public private(set) var channel: [String: Emote]

    public init(global: [String: Emote] = [:], channel: [String: Emote] = [:]) {
        self.global = global
        self.channel = channel
    }

    public func lookup(_ word: String) -> Emote? {
        channel[word] ?? global[word]
    }

    public mutating func setChannel(_ emotes: [String: Emote]) {
        channel = emotes
    }

    public mutating func setGlobal(_ emotes: [String: Emote]) {
        global = emotes
    }

    public mutating func apply(_ update: EmoteSetUpdate) {
        for emote in update.added { channel[emote.name] = emote }
        for name in update.removed { channel.removeValue(forKey: name) }
    }

    /// Layers providers by precedence so a higher-precedence provider keeps its emote name.
    public static func merge(_ groups: [EmoteProvider: [Emote]]) -> [String: Emote] {
        var result: [String: Emote] = [:]
        for provider in EmoteProvider.allCases.sorted(by: { $0.precedence > $1.precedence }) {
            for emote in groups[provider] ?? [] {
                result[emote.name] = emote
            }
        }
        return result
    }
}

public struct EmoteSetUpdate: Sendable, Equatable {
    public let added: [Emote]
    public let removed: [String]
    public let actor: String?

    public init(added: [Emote], removed: [String], actor: String? = nil) {
        self.added = added
        self.removed = removed
        self.actor = actor
    }
}
