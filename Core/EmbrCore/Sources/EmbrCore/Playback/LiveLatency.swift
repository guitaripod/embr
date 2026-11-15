import Foundation

/// How close to the broadcast a live stream plays, which the worker shapes its playlists for.
///
/// `standard` is every viewer's: about 10 seconds behind the streamer. `hyper` is the experimental Hyper Low Latency
/// mode: the worker also lists Twitch's still-growing low-latency segments, about 6 to 7.5 seconds behind on channels
/// with Twitch's low latency on. It holds only on one variant at a time, because AVPlayer's adaptive switching reads
/// the growing segments as a slow network, so the player pins a quality in this mode.
public nonisolated enum LiveLatency: String, Sendable, CaseIterable {
    case standard
    case hyper

    /// The tallest picture Hyper Low Latency plays while the viewer leaves the quality on Auto.
    public static let hyperAutoMaxHeight = 720

    /// The quality Hyper Low Latency plays on Auto: the viewer's last pick when the stream offers it, otherwise the
    /// richest video variant no taller than `hyperAutoMaxHeight`, otherwise the smallest video variant. Nil when the
    /// master offers no video.
    public static func hyperQuality(from qualities: [StreamQuality], preferredName: String? = nil) -> StreamQuality? {
        let video = qualities.filter { !$0.isAudioOnly }
        if let preferredName, let preferred = video.first(where: { $0.name == preferredName }) {
            return preferred
        }
        let fitting = video.filter { (height(of: $0) ?? Int.max) <= hyperAutoMaxHeight }
        if let best = fitting.max(by: { rank($0) < rank($1) }) {
            return best
        }
        return video.min(by: { rank($0) < rank($1) })
    }

    /// The picture height in a `RESOLUTION` such as "1280x720".
    static func height(of quality: StreamQuality) -> Int? {
        guard let resolution = quality.resolution,
              let value = resolution.split(separator: "x").last else { return nil }
        return Int(value)
    }

    private static func rank(_ quality: StreamQuality) -> Int {
        quality.bandwidth ?? (height(of: quality) ?? 0)
    }
}

extension PlaybackResolution {
    /// The same Twitch session in another latency mode: the worker's master URL with `latency=hyper` for `.hyper` and
    /// without it for `.standard`, the rest of the URL kept byte for byte. Switching this way keeps Twitch's session,
    /// so it brings no fresh preroll.
    public func withLatency(_ latency: LiveLatency) -> PlaybackResolution {
        guard var components = URLComponents(url: masterPlaylistURL, resolvingAgainstBaseURL: false) else { return self }
        var items = (components.percentEncodedQueryItems ?? []).filter { $0.name != "latency" }
        if latency == .hyper { items.append(URLQueryItem(name: "latency", value: latency.rawValue)) }
        components.percentEncodedQueryItems = items.isEmpty ? nil : items
        guard let url = components.url else { return self }
        return PlaybackResolution(masterPlaylistURL: url, qualities: qualities, expiresAt: expiresAt)
    }
}
