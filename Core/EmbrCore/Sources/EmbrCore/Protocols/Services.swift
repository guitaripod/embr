import Foundation

public protocol TwitchAPIProviding: Sendable {
    func topStreams(after: String?, first: Int) async throws -> Page<LiveStream>
    func streams(gameID: String, after: String?, first: Int) async throws -> Page<LiveStream>
    func followedStreams(userID: String, after: String?, first: Int) async throws -> Page<LiveStream>
    func streams(userIDs: [String]) async throws -> [LiveStream]
    func topCategories(after: String?, first: Int) async throws -> Page<GameCategory>
    func searchCategories(query: String, after: String?, first: Int) async throws -> Page<GameCategory>
    func searchChannels(query: String, liveOnly: Bool, after: String?, first: Int) async throws -> Page<ChannelInfo>
    func user(login: String) async throws -> TwitchUser?
    func users(ids: [String]) async throws -> [TwitchUser]
    func channelInfo(broadcasterID: String) async throws -> ChannelInfo?
    func videos(userID: String, after: String?, first: Int) async throws -> Page<VideoOnDemand>
    func clips(broadcasterID: String, after: String?, first: Int) async throws -> Page<Clip>
    func followedChannels(userID: String, after: String?, first: Int) async throws -> Page<FollowedChannel>
    func globalEmotes() async throws -> [Emote]
    func channelEmotes(broadcasterID: String) async throws -> [Emote]
    func globalBadges() async throws -> [Badge]
    func channelBadges(broadcasterID: String) async throws -> [Badge]
    func roomState(broadcasterID: String, moderatorID: String?) async throws -> RoomState
    func sendMessage(broadcasterID: String, senderID: String, text: String, replyParentMessageID: String?) async throws -> SendResult
    func banUser(broadcasterID: String, moderatorID: String, userID: String, duration: Int?, reason: String?) async throws
    func unbanUser(broadcasterID: String, moderatorID: String, userID: String) async throws
    func deleteMessage(broadcasterID: String, moderatorID: String, messageID: String?) async throws
}

public protocol ChatSource: Sendable {
    func start() -> AsyncStream<ChatEvent>
    func stop() async
    func send(_ text: String, replyParentID: String?) async throws -> SendResult
    /// Nudge the source to reconnect if its connection is stale or has given up
    /// (e.g. on app foreground or network restore).
    func wake() async
}

public extension ChatSource {
    func wake() async {}
}

public protocol ThirdPartyEmoteSource: Sendable {
    var provider: EmoteProvider { get }
    func globalEmotes() async throws -> [Emote]
    func channelEmotes(twitchUserID: String) async throws -> [Emote]
}

public protocol EmoteEventStreaming: Sendable {
    func updates(emoteSetID: String) -> AsyncStream<EmoteSetUpdate>
}

public protocol EmoteCataloging: Sendable {
    func loadGlobal() async -> (emotes: EmoteCatalog, badges: BadgeCatalog)
    func loadChannel(broadcasterID: String, login: String) async -> (emotes: EmoteCatalog, badges: BadgeCatalog)
}

public protocol PlaybackResolving: Sendable {
    func resolveLive(channelLogin: String) async throws -> PlaybackResolution
    func resolveVOD(videoID: String) async throws -> PlaybackResolution
}

public protocol TokenStoring: Sendable {
    func load() async -> StoredCredentials?
    func save(_ credentials: StoredCredentials) async
    func clear() async
}

public protocol AuthControlling: Sendable {
    func currentUser() async -> AuthenticatedUser?
    func logout() async
    func validAccessToken() async throws -> String
    func appAccessToken() async throws -> String
}

public protocol RecentMessagesProviding: Sendable {
    func recentMessages(channelLogin: String, limit: Int) async -> [ChatMessage]
}
