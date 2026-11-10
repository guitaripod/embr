import Foundation

/// What the channel page plays and shows: chat only, audio only, and whether a TV has the picture through AirPlay or a
/// mirrored screen.
nonisolated struct ChannelPlaybackMode: Equatable, Sendable {
    var chatOnly = false
    var audioOnly = false
    var externalRoute: ExternalRoute?

    /// The video area is on the page; while a TV has the picture it says where the stream plays.
    var showsVideo: Bool { !chatOnly && !audioOnly }

    /// Chat only stops the stream on this device, but a stream a TV is playing keeps playing there.
    var streamPlays: Bool { !chatOnly || externalRoute != nil }

    /// The compact player above chat: audio playing alone, or a TV playing the stream while the page shows only chat.
    var showsMiniPlayer: Bool { audioOnly || (chatOnly && externalRoute != nil) }
}
