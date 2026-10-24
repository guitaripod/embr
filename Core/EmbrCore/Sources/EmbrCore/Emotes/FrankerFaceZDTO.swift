import Foundation

public enum FrankerFaceZDTO {
    struct GlobalResponse: Decodable {
        let default_sets: [Int]?
        let sets: [String: EmoteSet]?
    }

    struct RoomResponse: Decodable {
        let room: Room?
        let sets: [String: EmoteSet]?
    }

    struct Room: Decodable {
        let set: Int?
    }

    struct EmoteSet: Decodable {
        let emoticons: [Emoticon]?
    }

    struct Emoticon: Decodable {
        let id: Int
        let name: String
        let width: Int?
        let height: Int?
        let urls: [String: String]?
        let animated: [String: String]?
        let modifier: Bool?
        let modifier_flags: Int?
    }

    public static func globalEmotes(_ data: Data) throws -> [Emote] {
        let response = try TwitchJSON.decode(GlobalResponse.self, from: data)
        let sets = response.sets ?? [:]
        let defaults = response.default_sets ?? []
        var emotes: [Emote] = []
        for id in defaults {
            guard let set = sets[String(id)] else { continue }
            emotes.append(contentsOf: (set.emoticons ?? []).map(map))
        }
        return emotes
    }

    public static func roomEmotes(_ data: Data) throws -> [Emote] {
        let response = try TwitchJSON.decode(RoomResponse.self, from: data)
        guard let setID = response.room?.set, let set = response.sets?[String(setID)] else { return [] }
        return (set.emoticons ?? []).map(map)
    }

    static func map(_ emoticon: Emoticon) -> Emote {
        let isAnimated = emoticon.animated != nil
        let source = isAnimated ? (emoticon.animated ?? [:]) : (emoticon.urls ?? [:])

        var urls: [EmoteScale: URL] = [:]
        for (key, value) in source {
            guard let scale = scale(forKey: key), let url = normalize(value) else { continue }
            urls[scale] = url
        }

        var ratio = 1.0
        if let w = emoticon.width, let h = emoticon.height, h > 0 {
            ratio = Double(w) / Double(h)
        }

        return Emote(
            id: String(emoticon.id),
            name: emoticon.name,
            provider: .frankerFaceZ,
            images: EmoteImageSet(urlsByScale: urls),
            isAnimated: isAnimated,
            isZeroWidth: emoticon.modifier == true,
            aspectRatio: ratio,
            ownerID: nil
        )
    }

    private static func normalize(_ url: String) -> URL? {
        guard !url.isEmpty else { return nil }
        let absolute = url.hasPrefix("//") ? "https:\(url)" : url
        return URL(string: absolute)
    }

    private static func scale(forKey key: String) -> EmoteScale? {
        switch key {
        case "1": return .x1
        case "2": return .x2
        case "4": return .x4
        default: return nil
        }
    }
}
