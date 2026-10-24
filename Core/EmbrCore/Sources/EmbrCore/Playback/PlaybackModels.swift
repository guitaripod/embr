import Foundation

public struct PlaybackResolution: Sendable, Equatable {
    public let masterPlaylistURL: URL
    public let qualities: [StreamQuality]
    public let expiresAt: Date?

    public init(masterPlaylistURL: URL, qualities: [StreamQuality] = [], expiresAt: Date? = nil) {
        self.masterPlaylistURL = masterPlaylistURL
        self.qualities = qualities
        self.expiresAt = expiresAt
    }
}

public struct StreamQuality: Sendable, Equatable, Hashable, Identifiable {
    public let name: String
    public let url: URL
    public let bandwidth: Int?
    public let resolution: String?
    public let frameRate: Double?
    public let isAudioOnly: Bool

    public var id: String { name }

    public init(name: String, url: URL, bandwidth: Int? = nil, resolution: String? = nil, frameRate: Double? = nil, isAudioOnly: Bool = false) {
        self.name = name
        self.url = url
        self.bandwidth = bandwidth
        self.resolution = resolution
        self.frameRate = frameRate
        self.isAudioOnly = isAudioOnly
    }
}

public struct HLSVariant: Sendable, Equatable {
    public let url: String
    public let bandwidth: Int?
    public let resolution: String?
    public let frameRate: Double?
    public let videoName: String?
    public let groupID: String?

    public init(url: String, bandwidth: Int?, resolution: String?, frameRate: Double?, videoName: String?, groupID: String?) {
        self.url = url
        self.bandwidth = bandwidth
        self.resolution = resolution
        self.frameRate = frameRate
        self.videoName = videoName
        self.groupID = groupID
    }
}

public struct HLSSegment: Sendable, Equatable {
    public let uri: String
    public let duration: Double
    public let isPrefetch: Bool
    public let attachedTags: [String]

    public init(uri: String, duration: Double, isPrefetch: Bool, attachedTags: [String]) {
        self.uri = uri
        self.duration = duration
        self.isPrefetch = isPrefetch
        self.attachedTags = attachedTags
    }
}
