import Foundation
import EmbrCore

final class TwitchAPIClient: TwitchAPIProviding {
    static let shared = TwitchAPIClient()

    private let transport: HTTPTransport
    private let auth: AuthControlling
    private let factory: HelixRequestFactory
    private let logger = AppLogger.shared

    init(
        transport: HTTPTransport = URLSessionTransport.shared,
        auth: AuthControlling = AuthService.shared,
        clientID: String = Configuration.current.twitchClientID
    ) {
        self.transport = transport
        self.auth = auth
        self.factory = HelixRequestFactory(clientID: clientID)
    }

    func topStreams(after: String?, first: Int) async throws -> Page<LiveStream> {
        let token = try await browseToken()
        let response = try await perform(factory.topStreams(first: first, after: after, token: token))
        return try page(response, decoding: StreamDTO.self, map: Self.liveStream)
    }

    func streams(gameID: String, after: String?, first: Int) async throws -> Page<LiveStream> {
        let token = try await browseToken()
        let response = try await perform(factory.streamsByGame(gameID: gameID, first: first, after: after, token: token))
        return try page(response, decoding: StreamDTO.self, map: Self.liveStream)
    }

    func followedStreams(userID: String, after: String?, first: Int) async throws -> Page<LiveStream> {
        let token = try await userToken()
        let response = try await perform(factory.followedStreams(userID: userID, first: first, after: after, token: token))
        return try page(response, decoding: StreamDTO.self, map: Self.liveStream)
    }

    func streams(userIDs: [String]) async throws -> [LiveStream] {
        guard !userIDs.isEmpty else { return [] }
        let token = try await browseToken()
        let response = try await perform(factory.streamsByUserIDs(userIDs, token: token))
        return try list(response, decoding: StreamDTO.self, map: Self.liveStream)
    }

    func topCategories(after: String?, first: Int) async throws -> Page<GameCategory> {
        let token = try await browseToken()
        let response = try await perform(factory.topGames(first: first, after: after, token: token))
        return try page(response, decoding: GameDTO.self, map: Self.gameCategory)
    }

    func searchCategories(query: String, after: String?, first: Int) async throws -> Page<GameCategory> {
        let token = try await browseToken()
        let response = try await perform(factory.searchCategories(query: query, first: first, after: after, token: token))
        return try page(response, decoding: GameDTO.self, map: Self.gameCategory)
    }

    func searchChannels(query: String, liveOnly: Bool, after: String?, first: Int) async throws -> Page<ChannelInfo> {
        let token = try await browseToken()
        let response = try await perform(factory.searchChannels(query: query, liveOnly: liveOnly, first: first, after: after, token: token))
        return try page(response, decoding: ChannelSearchDTO.self, map: Self.channelInfo)
    }

    func user(login: String) async throws -> TwitchUser? {
        let token = try await browseToken()
        let response = try await perform(factory.usersByLogins([login], token: token))
        return try list(response, decoding: UserDTO.self, map: Self.user).first
    }

    func users(ids: [String]) async throws -> [TwitchUser] {
        guard !ids.isEmpty else { return [] }
        let token = try await browseToken()
        let response = try await perform(factory.usersByIDs(ids, token: token))
        return try list(response, decoding: UserDTO.self, map: Self.user)
    }

    func channelInfo(broadcasterID: String) async throws -> ChannelInfo? {
        let token = try await browseToken()
        let response = try await perform(factory.channelInformation(broadcasterID: broadcasterID, token: token))
        return try list(response, decoding: ChannelDTO.self, map: Self.channelInfo).first
    }

    func videos(userID: String, after: String?, first: Int) async throws -> Page<VideoOnDemand> {
        let token = try await browseToken()
        let response = try await perform(factory.videos(userID: userID, first: first, after: after, token: token))
        return try page(response, decoding: VideoDTO.self, map: Self.video)
    }

    func clips(broadcasterID: String, after: String?, first: Int) async throws -> Page<Clip> {
        let token = try await browseToken()
        let response = try await perform(factory.clips(broadcasterID: broadcasterID, first: first, after: after, token: token))
        return try page(response, decoding: ClipDTO.self, map: Self.clip)
    }

    func followedChannels(userID: String, after: String?, first: Int) async throws -> Page<FollowedChannel> {
        let token = try await userToken()
        let response = try await perform(factory.followedChannels(userID: userID, first: first, after: after, token: token))
        return try page(response, decoding: FollowedChannelDTO.self, map: Self.followedChannel)
    }

    func globalEmotes() async throws -> [Emote] {
        let token = try await browseToken()
        let response = try await perform(factory.globalEmotes(token: token))
        return try list(response, decoding: EmoteDTO.self, map: Self.emote)
    }

    func channelEmotes(broadcasterID: String) async throws -> [Emote] {
        let token = try await browseToken()
        let response = try await perform(factory.channelEmotes(broadcasterID: broadcasterID, token: token))
        return try list(response, decoding: EmoteDTO.self, map: Self.emote)
    }

    func globalBadges() async throws -> [Badge] {
        let token = try await browseToken()
        let response = try await perform(factory.globalBadges(token: token))
        return Self.badges(try decodeList(response, as: BadgeSetDTO.self))
    }

    func channelBadges(broadcasterID: String) async throws -> [Badge] {
        let token = try await browseToken()
        let response = try await perform(factory.channelBadges(broadcasterID: broadcasterID, token: token))
        return Self.badges(try decodeList(response, as: BadgeSetDTO.self))
    }

    func roomState(broadcasterID: String, moderatorID: String?) async throws -> RoomState {
        let token = try await browseToken()
        let response = try await perform(factory.chatSettings(broadcasterID: broadcasterID, moderatorID: moderatorID, token: token))
        guard let dto = try decodeList(response, as: ChatSettingsDTO.self).first else {
            throw APIError.decoding("Missing chat settings")
        }
        return Self.roomState(dto)
    }

    func sendMessage(broadcasterID: String, senderID: String, text: String, replyParentMessageID: String?) async throws -> SendResult {
        let token = try await userToken()
        let response = try await perform(
            factory.sendChatMessage(
                broadcasterID: broadcasterID,
                senderID: senderID,
                message: text,
                replyParentMessageID: replyParentMessageID,
                token: token
            )
        )
        guard let dto = try decodeList(response, as: SendMessageResultDTO.self).first else {
            throw APIError.decoding("Missing send result")
        }
        return Self.sendResult(dto)
    }

    func banUser(broadcasterID: String, moderatorID: String, userID: String, duration: Int?, reason: String?) async throws {
        let token = try await userToken()
        let response = try await transport.send(
            factory.banUser(
                broadcasterID: broadcasterID,
                moderatorID: moderatorID,
                userID: userID,
                duration: duration,
                reason: reason,
                token: token
            )
        )
        try expectNoContent(response)
    }

    func unbanUser(broadcasterID: String, moderatorID: String, userID: String) async throws {
        let token = try await userToken()
        let response = try await transport.send(
            factory.unbanUser(broadcasterID: broadcasterID, moderatorID: moderatorID, userID: userID, token: token)
        )
        try expectNoContent(response)
    }

    func deleteMessage(broadcasterID: String, moderatorID: String, messageID: String?) async throws {
        let token = try await userToken()
        let response = try await transport.send(
            factory.deleteMessage(broadcasterID: broadcasterID, moderatorID: moderatorID, messageID: messageID, token: token)
        )
        try expectNoContent(response)
    }

    private func userToken() async throws -> String {
        try await auth.validAccessToken()
    }

    private func browseToken() async throws -> String {
        if let token = try? await auth.validAccessToken() {
            return token
        }
        return try await auth.appAccessToken()
    }

    private func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        let response = try await transport.send(request)
        guard response.isSuccess else { throw mappedError(response) }
        return response
    }

    private func expectNoContent(_ response: HTTPResponse) throws {
        guard response.isSuccess else { throw mappedError(response) }
    }

    private func mappedError(_ response: HTTPResponse) -> APIError {
        let error = APIError.from(status: response.status, rateLimitReset: response.rateLimit?.resetAt)
        logger.error("Helix \(response.status): \(error)", category: .api)
        return error
    }

    private func decodeList<DTO: Decodable & Sendable>(_ response: HTTPResponse, as type: DTO.Type) throws -> [DTO] {
        try TwitchJSON.decode(HelixResponse<DTO>.self, from: response.body).data
    }

    private func page<DTO: Decodable & Sendable, Element>(
        _ response: HTTPResponse,
        decoding type: DTO.Type,
        map: (DTO) -> Element
    ) throws -> Page<Element> where Element: Sendable & Equatable {
        let decoded = try TwitchJSON.decode(HelixResponse<DTO>.self, from: response.body)
        return Page(items: decoded.data.map(map), cursor: decoded.pagination?.cursor)
    }

    private func list<DTO: Decodable & Sendable, Element>(
        _ response: HTTPResponse,
        decoding type: DTO.Type,
        map: (DTO) -> Element
    ) throws -> [Element] {
        try decodeList(response, as: type).map(map)
    }
}

private extension TwitchAPIClient {
    static func liveStream(_ dto: StreamDTO) -> LiveStream {
        LiveStream(
            id: dto.id,
            userID: dto.userID,
            userLogin: dto.userLogin,
            userName: dto.userName,
            gameID: dto.gameID,
            gameName: dto.gameName,
            title: dto.title,
            viewerCount: dto.viewerCount,
            startedAt: dto.startedAt,
            language: dto.language,
            thumbnailURLTemplate: dto.thumbnailURL,
            tags: dto.tags ?? [],
            isMature: dto.isMature ?? false
        )
    }

    static func gameCategory(_ dto: GameDTO) -> GameCategory {
        GameCategory(id: dto.id, name: dto.name, boxArtURLTemplate: dto.boxArtURL)
    }

    static func channelInfo(_ dto: ChannelSearchDTO) -> ChannelInfo {
        ChannelInfo(
            id: dto.id,
            broadcasterLogin: dto.broadcasterLogin,
            broadcasterName: dto.displayName,
            gameID: dto.gameID,
            gameName: dto.gameName,
            title: dto.title,
            language: "",
            tags: dto.tags ?? []
        )
    }

    static func channelInfo(_ dto: ChannelDTO) -> ChannelInfo {
        ChannelInfo(
            id: dto.broadcasterID,
            broadcasterLogin: dto.broadcasterLogin,
            broadcasterName: dto.broadcasterName,
            gameID: dto.gameID,
            gameName: dto.gameName,
            title: dto.title,
            language: dto.broadcasterLanguage,
            tags: dto.tags ?? []
        )
    }

    static func user(_ dto: UserDTO) -> TwitchUser {
        TwitchUser(
            id: dto.id,
            login: dto.login,
            displayName: dto.displayName,
            profileImageURL: dto.profileImageURL.flatMap(URL.init(string:)),
            description: dto.description ?? "",
            broadcasterType: dto.broadcasterType ?? "",
            createdAt: dto.createdAt
        )
    }

    static func video(_ dto: VideoDTO) -> VideoOnDemand {
        VideoOnDemand(
            id: dto.id,
            userID: dto.userID,
            userLogin: dto.userLogin,
            userName: dto.userName,
            title: dto.title,
            createdAt: dto.createdAt,
            publishedAt: dto.publishedAt,
            thumbnailURLTemplate: dto.thumbnailURL,
            viewCount: dto.viewCount,
            durationSeconds: HelixDuration.seconds(from: dto.duration),
            type: dto.type
        )
    }

    static func clip(_ dto: ClipDTO) -> Clip {
        Clip(
            id: dto.id,
            broadcasterID: dto.broadcasterID,
            broadcasterName: dto.broadcasterName,
            creatorName: dto.creatorName,
            title: dto.title,
            viewCount: dto.viewCount,
            createdAt: dto.createdAt,
            thumbnailURL: dto.thumbnailURL.flatMap(URL.init(string:)),
            duration: dto.duration,
            url: dto.url.flatMap(URL.init(string:))
        )
    }

    static func followedChannel(_ dto: FollowedChannelDTO) -> FollowedChannel {
        FollowedChannel(
            id: dto.broadcasterID,
            broadcasterLogin: dto.broadcasterLogin,
            broadcasterName: dto.broadcasterName,
            followedAt: dto.followedAt
        )
    }

    static func emote(_ dto: EmoteDTO) -> Emote {
        var urls: [EmoteScale: URL] = [:]
        if let raw = dto.images.url1x, let url = URL(string: raw) { urls[.x1] = url }
        if let raw = dto.images.url2x, let url = URL(string: raw) { urls[.x2] = url }
        if let raw = dto.images.url4x, let url = URL(string: raw) { urls[.x4] = url }
        let isAnimated = dto.format?.contains("animated") ?? false
        return Emote(
            id: dto.id,
            name: dto.name,
            provider: .twitch,
            images: EmoteImageSet(urlsByScale: urls),
            isAnimated: isAnimated,
            isZeroWidth: false,
            ownerID: dto.ownerID
        )
    }

    static func badges(_ dtos: [BadgeSetDTO]) -> [Badge] {
        var result: [Badge] = []
        for set in dtos {
            for version in set.versions {
                var urls: [EmoteScale: URL] = [:]
                if let raw = version.imageURL1x, let url = URL(string: raw) { urls[.x1] = url }
                if let raw = version.imageURL2x, let url = URL(string: raw) { urls[.x2] = url }
                if let raw = version.imageURL4x, let url = URL(string: raw) { urls[.x4] = url }
                result.append(
                    Badge(
                        id: version.id,
                        setID: set.setID,
                        version: version.id,
                        title: version.title ?? "",
                        provider: .twitch,
                        images: EmoteImageSet(urlsByScale: urls)
                    )
                )
            }
        }
        return result
    }

    static func roomState(_ dto: ChatSettingsDTO) -> RoomState {
        RoomState(
            emoteOnly: dto.emoteMode,
            followersOnly: dto.followerMode ? (dto.followerModeDuration ?? 0) : nil,
            subscribersOnly: dto.subscriberMode,
            slowMode: dto.slowMode ? (dto.slowModeWaitTime ?? 0) : nil,
            uniqueChat: dto.uniqueChatMode
        )
    }
}

private struct StreamDTO: Decodable, Sendable {
    let id: String
    let userID: String
    let userLogin: String
    let userName: String
    let gameID: String
    let gameName: String
    let title: String
    let viewerCount: Int
    let startedAt: Date
    let language: String
    let thumbnailURL: String
    let tags: [String]?
    let isMature: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case userLogin = "user_login"
        case userName = "user_name"
        case gameID = "game_id"
        case gameName = "game_name"
        case title
        case viewerCount = "viewer_count"
        case startedAt = "started_at"
        case language
        case thumbnailURL = "thumbnail_url"
        case tags
        case isMature = "is_mature"
    }
}

private struct GameDTO: Decodable, Sendable {
    let id: String
    let name: String
    let boxArtURL: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case boxArtURL = "box_art_url"
    }
}

private struct ChannelSearchDTO: Decodable, Sendable {
    let id: String
    let broadcasterLogin: String
    let displayName: String
    let gameID: String
    let gameName: String
    let title: String
    let isLive: Bool
    let tags: [String]?
    let thumbnailURL: String

    enum CodingKeys: String, CodingKey {
        case id
        case broadcasterLogin = "broadcaster_login"
        case displayName = "display_name"
        case gameID = "game_id"
        case gameName = "game_name"
        case title
        case isLive = "is_live"
        case tags
        case thumbnailURL = "thumbnail_url"
    }
}

private struct UserDTO: Decodable, Sendable {
    let id: String
    let login: String
    let displayName: String
    let profileImageURL: String?
    let description: String?
    let broadcasterType: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case displayName = "display_name"
        case profileImageURL = "profile_image_url"
        case description
        case broadcasterType = "broadcaster_type"
        case createdAt = "created_at"
    }
}

private struct ChannelDTO: Decodable, Sendable {
    let broadcasterID: String
    let broadcasterLogin: String
    let broadcasterName: String
    let gameID: String
    let gameName: String
    let title: String
    let broadcasterLanguage: String
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case broadcasterID = "broadcaster_id"
        case broadcasterLogin = "broadcaster_login"
        case broadcasterName = "broadcaster_name"
        case gameID = "game_id"
        case gameName = "game_name"
        case title
        case broadcasterLanguage = "broadcaster_language"
        case tags
    }
}

private struct VideoDTO: Decodable, Sendable {
    let id: String
    let userID: String
    let userLogin: String
    let userName: String
    let title: String
    let createdAt: Date
    let publishedAt: Date
    let thumbnailURL: String
    let viewCount: Int
    let duration: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case userLogin = "user_login"
        case userName = "user_name"
        case title
        case createdAt = "created_at"
        case publishedAt = "published_at"
        case thumbnailURL = "thumbnail_url"
        case viewCount = "view_count"
        case duration
        case type
    }
}

private struct ClipDTO: Decodable, Sendable {
    let id: String
    let broadcasterID: String
    let broadcasterName: String
    let creatorName: String
    let title: String
    let viewCount: Int
    let createdAt: Date
    let thumbnailURL: String?
    let duration: Double
    let url: String?

    enum CodingKeys: String, CodingKey {
        case id
        case broadcasterID = "broadcaster_id"
        case broadcasterName = "broadcaster_name"
        case creatorName = "creator_name"
        case title
        case viewCount = "view_count"
        case createdAt = "created_at"
        case thumbnailURL = "thumbnail_url"
        case duration
        case url
    }
}

private struct FollowedChannelDTO: Decodable, Sendable {
    let broadcasterID: String
    let broadcasterLogin: String
    let broadcasterName: String
    let followedAt: Date

    enum CodingKeys: String, CodingKey {
        case broadcasterID = "broadcaster_id"
        case broadcasterLogin = "broadcaster_login"
        case broadcasterName = "broadcaster_name"
        case followedAt = "followed_at"
    }
}

private struct EmoteImagesDTO: Decodable, Sendable {
    let url1x: String?
    let url2x: String?
    let url4x: String?

    enum CodingKeys: String, CodingKey {
        case url1x = "url_1x"
        case url2x = "url_2x"
        case url4x = "url_4x"
    }
}

private struct EmoteDTO: Decodable, Sendable {
    let id: String
    let name: String
    let images: EmoteImagesDTO
    let format: [String]?
    let scale: [String]?
    let themeMode: [String]?
    let emoteType: String?
    let emoteSetID: String?
    let ownerID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case images
        case format
        case scale
        case themeMode = "theme_mode"
        case emoteType = "emote_type"
        case emoteSetID = "emote_set_id"
        case ownerID = "owner_id"
    }
}

private struct BadgeVersionDTO: Decodable, Sendable {
    let id: String
    let imageURL1x: String?
    let imageURL2x: String?
    let imageURL4x: String?
    let title: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id
        case imageURL1x = "image_url_1x"
        case imageURL2x = "image_url_2x"
        case imageURL4x = "image_url_4x"
        case title
        case description
    }
}

private struct BadgeSetDTO: Decodable, Sendable {
    let setID: String
    let versions: [BadgeVersionDTO]

    enum CodingKeys: String, CodingKey {
        case setID = "set_id"
        case versions
    }
}

private struct ChatSettingsDTO: Decodable, Sendable {
    let emoteMode: Bool
    let followerMode: Bool
    let followerModeDuration: Int?
    let slowMode: Bool
    let slowModeWaitTime: Int?
    let subscriberMode: Bool
    let uniqueChatMode: Bool

    enum CodingKeys: String, CodingKey {
        case emoteMode = "emote_mode"
        case followerMode = "follower_mode"
        case followerModeDuration = "follower_mode_duration"
        case slowMode = "slow_mode"
        case slowModeWaitTime = "slow_mode_wait_time"
        case subscriberMode = "subscriber_mode"
        case uniqueChatMode = "unique_chat_mode"
    }
}

private struct DropReasonDTO: Decodable, Sendable {
    let code: String
    let message: String
}

private struct SendMessageResultDTO: Decodable, Sendable {
    let messageID: String?
    let isSent: Bool
    let dropReason: DropReasonDTO?

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case isSent = "is_sent"
        case dropReason = "drop_reason"
    }
}

private extension TwitchAPIClient {
    static func sendResult(_ dto: SendMessageResultDTO) -> SendResult {
        SendResult(
            messageID: dto.messageID,
            isSent: dto.isSent,
            dropReason: dto.dropReason.map { "\($0.code): \($0.message)" }
        )
    }
}
