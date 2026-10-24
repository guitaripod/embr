import Foundation

public enum SevenTVDTO {
    static let zeroWidthFlag = 256

    struct UserResponse: Decodable {
        let emote_set: EmoteSet?
    }

    struct EmoteSet: Decodable {
        let id: String?
        let emotes: [EmoteEntry]?
    }

    struct EmoteEntry: Decodable {
        let id: String
        let name: String
        let flags: Int?
        let data: EmoteData?
    }

    struct EmoteData: Decodable {
        let animated: Bool?
        let host: Host?
    }

    struct Host: Decodable {
        let url: String?
        let files: [HostFile]?
    }

    struct HostFile: Decodable {
        let name: String
        let format: String?
        let width: Int?
        let height: Int?
        let frame_count: Int?
    }

    public static func emotes(fromUser data: Data) throws -> (setID: String?, emotes: [Emote]) {
        let response = try TwitchJSON.decode(UserResponse.self, from: data)
        guard let set = response.emote_set else { return (nil, []) }
        return (set.id, map(set.emotes ?? []))
    }

    public static func emotes(fromGlobal data: Data) throws -> [Emote] {
        let set = try TwitchJSON.decode(EmoteSet.self, from: data)
        return map(set.emotes ?? [])
    }

    static func map(_ entries: [EmoteEntry]) -> [Emote] {
        entries.compactMap(map)
    }

    private static func map(_ entry: EmoteEntry) -> Emote? {
        guard let host = entry.data?.host, let baseURL = normalize(host.url) else { return nil }
        let webpFiles = (host.files ?? []).filter { ($0.format ?? "").uppercased() == "WEBP" }
        guard !webpFiles.isEmpty else { return nil }

        var urls: [EmoteScale: URL] = [:]
        var ratio = 1.0
        var maxFrames = 0
        for file in webpFiles {
            guard let scale = scale(forFileName: file.name) else { continue }
            if let url = URL(string: "\(baseURL)/\(file.name)") {
                urls[scale] = url
            }
            if let frames = file.frame_count { maxFrames = max(maxFrames, frames) }
            if scale == .x1, let w = file.width, let h = file.height, h > 0 {
                ratio = Double(w) / Double(h)
            }
        }
        guard !urls.isEmpty else { return nil }

        let flags = entry.flags ?? 0
        let isZeroWidth = (flags & zeroWidthFlag) != 0
        let isAnimated = (entry.data?.animated ?? false) || maxFrames > 1

        return Emote(
            id: entry.id,
            name: entry.name,
            provider: .sevenTV,
            images: EmoteImageSet(urlsByScale: urls),
            isAnimated: isAnimated,
            isZeroWidth: isZeroWidth,
            aspectRatio: ratio,
            ownerID: nil
        )
    }

    private static func normalize(_ url: String?) -> String? {
        guard let url, !url.isEmpty else { return nil }
        if url.hasPrefix("//") { return "https:\(url)" }
        return url
    }

    private static func scale(forFileName name: String) -> EmoteScale? {
        let prefix = name.prefix { $0 != "." }
        switch prefix {
        case "1x": return .x1
        case "2x": return .x2
        case "3x": return .x3
        case "4x": return .x4
        default: return nil
        }
    }
}
