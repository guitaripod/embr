import Foundation
import EmbrCore

/// A channel shown by its avatar: an offline favorite, a followed channel, a search result.
struct TVChannelSummary: Hashable, Sendable {
    let id: String
    let login: String
    let name: String
    let avatarURL: URL?
    let isLive: Bool

    var displayName: String { name.isEmpty ? login : name }
}

enum TVShelfItem: Hashable, Sendable {
    case stream(LiveStream)
    case category(GameCategory)
    case channel(TVChannelSummary)
    case video(VideoOnDemand)
    case clip(Clip)

    /// Stable across refreshes, so a viewer count that changes updates the card in place instead of replacing it and
    /// moving focus.
    var key: String {
        switch self {
        case .stream(let stream): "stream:\(stream.userID)"
        case .category(let category): "category:\(category.id)"
        case .channel(let channel): "channel:\(channel.id)"
        case .video(let video): "video:\(video.id)"
        case .clip(let clip): "clip:\(clip.id)"
        }
    }

    var channelLogin: String? {
        switch self {
        case .stream(let stream): stream.userLogin
        case .channel(let channel): channel.login
        case .video(let video): video.userLogin
        case .category, .clip: nil
        }
    }
}

struct TVShelf: Hashable, Sendable {
    enum Style: Hashable, Sendable {
        /// Two large live streams per screen width, for the first row of a tab.
        case featured
        case streams
        case categories
        case channels
        case videos
        /// Every stream of a category, wrapping into rows.
        case streamGrid
        case categoryGrid
    }

    let id: String
    let title: String?
    let style: Style
    var items: [TVShelfItem]
}
