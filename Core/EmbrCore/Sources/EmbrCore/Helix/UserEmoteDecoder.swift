import Foundation

/// Reads `GET /helix/chat/emotes/user`. That response carries a CDN template instead of the three image URLs the other
/// emote endpoints send, so the page is mapped once, while decoding, and every emote arrives ready to render.
public enum UserEmoteDecoder {
    public static func decode(_ data: Data) throws -> HelixResponse<UserEmote> {
        let page = try TwitchJSON.decode(HelixResponse<UserEmoteDTO>.self, from: data)
        return HelixResponse(
            data: page.data.map(map),
            pagination: page.pagination.map { .init(cursor: $0.cursor) },
            total: page.total
        )
    }

    private static func map(_ dto: UserEmoteDTO) -> UserEmote {
        UserEmote(
            emote: Emote(
                id: dto.id,
                name: dto.name,
                provider: .twitch,
                images: images(for: dto),
                isAnimated: dto.format?.contains("animated") ?? false,
                isZeroWidth: false,
                aspectRatio: 1.0,
                ownerID: dto.ownerID.flatMap { $0.isEmpty ? nil : $0 }
            ),
            emoteType: dto.emoteType ?? "",
            setID: dto.setID.flatMap { $0.isEmpty ? nil : $0 },
            ownerID: dto.ownerID.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private static func images(for dto: UserEmoteDTO) -> EmoteImageSet {
        let format = preferredFormat(dto.format)
        let theme = preferredTheme(dto.themeMode)
        let template = dto.template ?? "https://static-cdn.jtvnw.net/emoticons/v2/{{id}}/{{format}}/{{theme_mode}}/{{scale}}"
        let resolved = template
            .replacingOccurrences(of: "{{id}}", with: dto.id)
            .replacingOccurrences(of: "{{format}}", with: format)
            .replacingOccurrences(of: "{{theme_mode}}", with: theme)
        var urls: [EmoteScale: URL] = [:]
        for (scale, value) in [("1.0", EmoteScale.x1), ("2.0", .x2), ("3.0", .x3)] {
            let raw = resolved.replacingOccurrences(of: "{{scale}}", with: scale)
            if let url = URL(string: raw) {
                urls[value] = url
            }
        }
        return EmoteImageSet(urlsByScale: urls)
    }

    private static func preferredFormat(_ formats: [String]?) -> String {
        guard let formats, !formats.isEmpty else { return "static" }
        return formats.contains("static") ? "static" : formats[0]
    }

    private static func preferredTheme(_ themes: [String]?) -> String {
        guard let themes, !themes.isEmpty else { return "dark" }
        return themes.contains("dark") ? "dark" : themes[0]
    }
}

struct UserEmoteDTO: Decodable, Sendable {
    let id: String
    let name: String
    let emoteType: String?
    let setID: String?
    let ownerID: String?
    let format: [String]?
    let themeMode: [String]?
    let template: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case emoteType = "emote_type"
        case setID = "emote_set_id"
        case ownerID = "owner_id"
        case format
        case themeMode = "theme_mode"
        case template
    }
}
