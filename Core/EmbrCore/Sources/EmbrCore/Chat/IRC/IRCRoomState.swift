import Foundation

public extension IRCMapper {
    /// Merges a Twitch IRC `ROOMSTATE` message onto an existing `RoomState`.
    ///
    /// The initial `ROOMSTATE` on JOIN carries every mode tag; later messages carry
    /// only the tags that changed, so absent tags must preserve the prior value.
    /// `followers-only` uses Twitch's convention: `-1` off, `0` any follower, `N` minutes.
    /// `r9k` maps to `uniqueChat`.
    static func roomState(from msg: IRCMessage, merging base: RoomState) -> RoomState {
        var state = base
        if let value = msg.tags["emote-only"] { state.emoteOnly = value == "1" }
        if let value = msg.tags["subs-only"] { state.subscribersOnly = value == "1" }
        if let value = msg.tags["r9k"] { state.uniqueChat = value == "1" }
        if let value = msg.tags["slow"], let seconds = Int(value) {
            state.slowMode = seconds == 0 ? nil : seconds
        }
        if let value = msg.tags["followers-only"], let minutes = Int(value) {
            state.followersOnly = minutes < 0 ? nil : minutes
        }
        return state
    }
}
