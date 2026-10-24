import Foundation

public enum BetterTTVDTO {
    static let zeroWidthCodes: Set<String> = [
        "cvMask", "cvHazmat", "SoSnowy", "IceCold",
        "SantaHat", "TopHat", "ReinDeer", "CandyCane"
    ]

    struct EmoteEntry: Decodable {
        let id: String
        let code: String
        let imageType: String?
        let animated: Bool?
    }

    struct ChannelResponse: Decodable {
        let channelEmotes: [EmoteEntry]?
        let sharedEmotes: [EmoteEntry]?
    }

    public static func globalEmotes(_ data: Data) throws -> [Emote] {
        let entries = try TwitchJSON.decode([EmoteEntry].self, from: data)
        return entries.map(map)
    }

    public static func channelEmotes(_ data: Data) throws -> [Emote] {
        let response = try TwitchJSON.decode(ChannelResponse.self, from: data)
        let combined = (response.channelEmotes ?? []) + (response.sharedEmotes ?? [])
        return combined.map(map)
    }

    static func map(_ entry: EmoteEntry) -> Emote {
        var urls: [EmoteScale: URL] = [:]
        for scale in [EmoteScale.x1, .x2, .x3] {
            if let url = URL(string: "https://cdn.betterttv.net/emote/\(entry.id)/\(scale.rawValue)x") {
                urls[scale] = url
            }
        }
        let imageType = (entry.imageType ?? "").lowercased()
        let isAnimated = (entry.animated ?? false) || imageType == "gif"
        return Emote(
            id: entry.id,
            name: entry.code,
            provider: .betterTTV,
            images: EmoteImageSet(urlsByScale: urls),
            isAnimated: isAnimated,
            isZeroWidth: zeroWidthCodes.contains(entry.code),
            aspectRatio: 1.0,
            ownerID: nil
        )
    }
}
