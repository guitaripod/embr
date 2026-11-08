import Foundation

enum HelixMappers {
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

    static func emotes(_ dtos: [EmoteDTO]) -> [Emote] {
        dtos.map(emote)
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

    static func sendResult(_ dto: SendMessageResultDTO) -> SendResult {
        SendResult(
            messageID: dto.messageID,
            isSent: dto.isSent,
            dropReason: dto.dropReason.map { "\($0.code): \($0.message)" }
        )
    }
}
