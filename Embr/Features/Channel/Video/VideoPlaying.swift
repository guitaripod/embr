import UIKit
import Combine
import EmbrCore

enum VideoState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case ended
    case error(String)
}

struct PlaybackProgress: Equatable, Sendable {
    var current: TimeInterval
    var duration: TimeInterval
    var isLive: Bool

    static let empty = PlaybackProgress(current: 0, duration: 0, isLive: true)

    var isSeekable: Bool { !isLive && duration.isFinite && duration > 0 }
}

@MainActor
protocol VideoPlaying: AnyObject {
    var view: UIView { get }
    var statePublisher: AnyPublisher<VideoState, Never> { get }
    var availableQualities: [StreamQuality] { get }
    var currentQuality: StreamQuality? { get }
    var latencyPublisher: AnyPublisher<TimeInterval?, Never> { get }
    var adBreakPublisher: AnyPublisher<TimeInterval?, Never> { get }
    var progressPublisher: AnyPublisher<PlaybackProgress, Never> { get }

    func load(_ resolution: PlaybackResolution)
    func play()
    func pause()
    func seek(to seconds: TimeInterval)
    func seekToLive()
    func setQuality(_ quality: StreamQuality)
    func setRate(_ rate: Float)
    func setMuted(_ muted: Bool)
    func teardown()
}
