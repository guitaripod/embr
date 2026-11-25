import Foundation

/// The properties of a channel that `PATCH /helix/channels` can change. Every field is optional and Twitch ignores
/// the ones left out, so one request can change one property without rewriting the rest.
public struct ChannelUpdate: Encodable, Sendable, Equatable {
    public let gameID: String?
    public let language: String?
    public let title: String?
    public let delay: Int?
    public let tags: [String]?
    public let contentClassificationLabels: [ContentClassificationLabel]?
    public let isBrandedContent: Bool?

    public init(
        gameID: String? = nil,
        language: String? = nil,
        title: String? = nil,
        delay: Int? = nil,
        tags: [String]? = nil,
        contentClassificationLabels: [ContentClassificationLabel]? = nil,
        isBrandedContent: Bool? = nil
    ) {
        self.gameID = gameID
        self.language = language
        self.title = title
        self.delay = delay
        self.tags = tags
        self.contentClassificationLabels = contentClassificationLabels
        self.isBrandedContent = isBrandedContent
    }

    enum CodingKeys: String, CodingKey {
        case gameID = "game_id"
        case language = "broadcaster_language"
        case title
        case delay
        case tags
        case contentClassificationLabels = "content_classification_labels"
        case isBrandedContent = "is_branded_content"
    }
}

/// One content classification label and whether the channel carries it. Twitch clears a channel's labels by sending
/// every label with `isEnabled` false.
public struct ContentClassificationLabel: Encodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let isEnabled: Bool

    public init(id: String, isEnabled: Bool) {
        self.id = id
        self.isEnabled = isEnabled
    }

    enum CodingKeys: String, CodingKey {
        case id
        case isEnabled = "is_enabled"
    }
}
