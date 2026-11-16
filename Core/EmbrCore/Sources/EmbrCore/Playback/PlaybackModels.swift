import Foundation

public struct PlaybackResolution: Sendable, Equatable {
    /// The master playlist to play.
    public let masterPlaylistURL: URL
    public let qualities: [StreamQuality]
    public let expiresAt: Date?
    /// The session's master in each latency mode: the standard one always, the Hyper one only when the worker handed
    /// it to a Founding Member.
    public let standardPlaylistURL: URL
    public let hyperPlaylistURL: URL?

    public init(masterPlaylistURL: URL, qualities: [StreamQuality] = [], expiresAt: Date? = nil, hyperPlaylistURL: URL? = nil) {
        self.masterPlaylistURL = masterPlaylistURL
        self.qualities = qualities
        self.expiresAt = expiresAt
        self.standardPlaylistURL = masterPlaylistURL
        self.hyperPlaylistURL = hyperPlaylistURL
    }

    private init(playing: URL, standard: URL, hyper: URL?, qualities: [StreamQuality], expiresAt: Date?) {
        self.masterPlaylistURL = playing
        self.qualities = qualities
        self.expiresAt = expiresAt
        self.standardPlaylistURL = standard
        self.hyperPlaylistURL = hyper
    }

    /// Whether this session can play in Hyper Low Latency.
    public var offersHyper: Bool { hyperPlaylistURL != nil }

    /// The latency mode the playing master is in.
    public var latency: LiveLatency {
        hyperPlaylistURL != nil && masterPlaylistURL == hyperPlaylistURL ? .hyper : .standard
    }

    /// The same Twitch session in another latency mode, so a switch brings no fresh preroll; standard when the
    /// session offers no Hyper link.
    public func withLatency(_ latency: LiveLatency) -> PlaybackResolution {
        let playing = latency == .hyper ? (hyperPlaylistURL ?? standardPlaylistURL) : standardPlaylistURL
        return PlaybackResolution(playing: playing, standard: standardPlaylistURL, hyper: hyperPlaylistURL, qualities: qualities, expiresAt: expiresAt)
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
