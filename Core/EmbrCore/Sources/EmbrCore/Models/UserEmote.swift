import Foundation

/// An emote the signed-in user can use anywhere, with the Twitch set it belongs to and the type that grants it
/// (subscriber, follower, Bits and the rest), which is what a picker groups by.
public struct UserEmote: Sendable, Equatable, Hashable, Identifiable {
    public let emote: Emote
    public let emoteType: String
    public let setID: String?
    public let ownerID: String?

    public var id: String { emote.id }
    public var name: String { emote.name }
    public var isAnimated: Bool { emote.isAnimated }

    public init(emote: Emote, emoteType: String, setID: String? = nil, ownerID: String? = nil) {
        self.emote = emote
        self.emoteType = emoteType
        self.setID = setID
        self.ownerID = ownerID
    }
}
