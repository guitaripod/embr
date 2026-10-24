import Foundation

public struct LiveStream: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let userID: String
    public let userLogin: String
    public let userName: String
    public let gameID: String
    public let gameName: String
    public let title: String
    public let viewerCount: Int
    public let startedAt: Date
    public let language: String
    public let thumbnailURLTemplate: String
    public let tags: [String]
    public let isMature: Bool

    public init(
        id: String,
        userID: String,
        userLogin: String,
        userName: String,
        gameID: String,
        gameName: String,
        title: String,
        viewerCount: Int,
        startedAt: Date,
        language: String,
        thumbnailURLTemplate: String,
        tags: [String] = [],
        isMature: Bool = false
    ) {
        self.id = id
        self.userID = userID
        self.userLogin = userLogin
        self.userName = userName
        self.gameID = gameID
        self.gameName = gameName
        self.title = title
        self.viewerCount = viewerCount
        self.startedAt = startedAt
        self.language = language
        self.thumbnailURLTemplate = thumbnailURLTemplate
        self.tags = tags
        self.isMature = isMature
    }

    public func thumbnailURL(width: Int, height: Int) -> URL? {
        let resolved = thumbnailURLTemplate
            .replacingOccurrences(of: "{width}", with: String(width))
            .replacingOccurrences(of: "{height}", with: String(height))
        return URL(string: resolved)
    }
}

public struct GameCategory: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let boxArtURLTemplate: String

    public init(id: String, name: String, boxArtURLTemplate: String) {
        self.id = id
        self.name = name
        self.boxArtURLTemplate = boxArtURLTemplate
    }

    public func boxArtURL(width: Int, height: Int) -> URL? {
        let resolved = boxArtURLTemplate
            .replacingOccurrences(of: "{width}", with: String(width))
            .replacingOccurrences(of: "{height}", with: String(height))
        return URL(string: resolved)
    }
}

public struct TwitchUser: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let login: String
    public let displayName: String
    public let profileImageURL: URL?
    public let description: String
    public let broadcasterType: String
    public let createdAt: Date?

    public init(
        id: String,
        login: String,
        displayName: String,
        profileImageURL: URL? = nil,
        description: String = "",
        broadcasterType: String = "",
        createdAt: Date? = nil
    ) {
        self.id = id
        self.login = login
        self.displayName = displayName
        self.profileImageURL = profileImageURL
        self.description = description
        self.broadcasterType = broadcasterType
        self.createdAt = createdAt
    }
}

public struct ChannelInfo: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let broadcasterLogin: String
    public let broadcasterName: String
    public let gameID: String
    public let gameName: String
    public let title: String
    public let language: String
    public let tags: [String]
    public let isLive: Bool

    public init(
        id: String,
        broadcasterLogin: String,
        broadcasterName: String,
        gameID: String,
        gameName: String,
        title: String,
        language: String,
        tags: [String] = [],
        isLive: Bool = false
    ) {
        self.id = id
        self.broadcasterLogin = broadcasterLogin
        self.broadcasterName = broadcasterName
        self.gameID = gameID
        self.gameName = gameName
        self.title = title
        self.language = language
        self.tags = tags
        self.isLive = isLive
    }
}

public struct VideoOnDemand: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let userID: String
    public let userLogin: String
    public let userName: String
    public let title: String
    public let createdAt: Date
    public let publishedAt: Date
    public let thumbnailURLTemplate: String
    public let viewCount: Int
    public let durationSeconds: Int
    public let type: String

    public init(
        id: String,
        userID: String,
        userLogin: String,
        userName: String,
        title: String,
        createdAt: Date,
        publishedAt: Date,
        thumbnailURLTemplate: String,
        viewCount: Int,
        durationSeconds: Int,
        type: String
    ) {
        self.id = id
        self.userID = userID
        self.userLogin = userLogin
        self.userName = userName
        self.title = title
        self.createdAt = createdAt
        self.publishedAt = publishedAt
        self.thumbnailURLTemplate = thumbnailURLTemplate
        self.viewCount = viewCount
        self.durationSeconds = durationSeconds
        self.type = type
    }
}

public struct Clip: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let broadcasterID: String
    public let broadcasterName: String
    public let creatorName: String
    public let title: String
    public let viewCount: Int
    public let createdAt: Date
    public let thumbnailURL: URL?
    public let duration: Double
    public let url: URL?

    public init(
        id: String,
        broadcasterID: String,
        broadcasterName: String,
        creatorName: String,
        title: String,
        viewCount: Int,
        createdAt: Date,
        thumbnailURL: URL? = nil,
        duration: Double = 0,
        url: URL? = nil
    ) {
        self.id = id
        self.broadcasterID = broadcasterID
        self.broadcasterName = broadcasterName
        self.creatorName = creatorName
        self.title = title
        self.viewCount = viewCount
        self.createdAt = createdAt
        self.thumbnailURL = thumbnailURL
        self.duration = duration
        self.url = url
    }
}

public struct FollowedChannel: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let broadcasterLogin: String
    public let broadcasterName: String
    public let followedAt: Date

    public init(id: String, broadcasterLogin: String, broadcasterName: String, followedAt: Date) {
        self.id = id
        self.broadcasterLogin = broadcasterLogin
        self.broadcasterName = broadcasterName
        self.followedAt = followedAt
    }
}

public struct ScheduleSegment: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let startTime: Date
    public let endTime: Date?
    public let title: String
    public let categoryName: String?
    public let isRecurring: Bool
    public let canceledUntil: Date?

    public init(
        id: String,
        startTime: Date,
        endTime: Date? = nil,
        title: String,
        categoryName: String? = nil,
        isRecurring: Bool = false,
        canceledUntil: Date? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.title = title
        self.categoryName = categoryName
        self.isRecurring = isRecurring
        self.canceledUntil = canceledUntil
    }
}
