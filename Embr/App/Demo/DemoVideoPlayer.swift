#if DEBUG
import UIKit
import Combine
import EmbrCore

/// Stands in for the video player in invented channels: the simulator cannot decode a live stream
/// and there is none to decode, so the picture is a procedural frame and playback is always on.
@MainActor
final class DemoVideoPlayer: VideoPlaying {
    var view: UIView { imageView }
    var statePublisher: AnyPublisher<VideoState, Never> { stateSubject.eraseToAnyPublisher() }
    var latencyPublisher: AnyPublisher<TimeInterval?, Never> { Just(2.4).eraseToAnyPublisher() }
    var adBreakPublisher: AnyPublisher<TimeInterval?, Never> { Just(nil).eraseToAnyPublisher() }
    var progressPublisher: AnyPublisher<PlaybackProgress, Never> { progressSubject.eraseToAnyPublisher() }

    private(set) var availableQualities: [StreamQuality] = []
    private(set) var currentQuality: StreamQuality?

    private let imageView = UIImageView()
    private let stateSubject = CurrentValueSubject<VideoState, Never>(.idle)
    private let progressSubject = CurrentValueSubject<PlaybackProgress, Never>(.empty)

    init() {
        imageView.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
    }

    func load(_ resolution: PlaybackResolution) {
        let parts = resolution.masterPlaylistURL.pathComponents.filter { $0 != "/" }
        let isVOD = parts.contains("vod") || parts.contains("clips")
        let key = Self.pictureKey(from: parts)
        imageView.image = DemoArt.stream(key: key, size: CGSize(width: 1280, height: 720), facecam: true)
        availableQualities = ["1080p60", "720p60", "480p", "360p"].compactMap { name in
            URL(string: "https://\(DemoWorld.host)/hls/\(key)/\(name).m3u8").map { StreamQuality(name: name, url: $0) }
        }
        if isVOD {
            progressSubject.send(PlaybackProgress(current: 2290, duration: 13272, isLive: false))
        }
        stateSubject.send(.playing)
    }

    private static func pictureKey(from parts: [String]) -> String {
        guard let last = parts.dropLast().last else { return DemoWorld.channels[0].login }
        let pieces = last.split(separator: "-").map(String.init)
        if parts.contains("vod") || parts.contains("clips"), pieces.count >= 3 { return pieces[1] + pieces[2] }
        return last
    }

    func play() { stateSubject.send(.playing) }
    func pause() { stateSubject.send(.paused) }
    func seek(to seconds: TimeInterval) {}
    func seekToLive() {}
    func setQuality(_ quality: StreamQuality) { currentQuality = quality }
    func setRate(_ rate: Float) {}
    func setMuted(_ muted: Bool) {}
    func teardown() {}
}
#endif
