import Foundation

public enum BadgeProvider: String, Sendable, Equatable, Hashable, Codable {
    case twitch
    case frankerFaceZ
    case betterTTV
    case sevenTV
    case chatterino
}

public struct Badge: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let setID: String
    public let version: String
    public let title: String
    public let provider: BadgeProvider
    public let images: EmoteImageSet
    public let isVector: Bool

    public init(
        id: String,
        setID: String,
        version: String,
        title: String,
        provider: BadgeProvider,
        images: EmoteImageSet,
        isVector: Bool = false
    ) {
        self.id = id
        self.setID = setID
        self.version = version
        self.title = title
        self.provider = provider
        self.images = images
        self.isVector = isVector
    }

    public static func key(setID: String, version: String) -> String {
        "\(setID)/\(version)"
    }
}

public struct BadgeCatalog: Sendable, Equatable {
    public private(set) var twitch: [String: Badge]
    public private(set) var userBadges: [String: [Badge]]

    public init(twitch: [String: Badge] = [:], userBadges: [String: [Badge]] = [:]) {
        self.twitch = twitch
        self.userBadges = userBadges
    }

    public mutating func setTwitch(_ badges: [String: Badge]) {
        twitch = badges
    }

    public mutating func setUserBadges(_ badges: [String: [Badge]]) {
        userBadges = badges
    }

    public func resolve(message: ChatMessage) -> [Badge] {
        var resolved: [Badge] = []
        for badge in message.badges {
            if let twitchBadge = twitch[Badge.key(setID: badge.setID, version: badge.id)] {
                resolved.append(twitchBadge)
            }
        }
        resolved.append(contentsOf: userBadges[message.author.id] ?? [])
        return resolved
    }
}
