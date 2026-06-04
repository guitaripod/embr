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

@MainActor
protocol VideoPlaying: AnyObject {
    var view: UIView { get }
    var statePublisher: AnyPublisher<VideoState, Never> { get }
    var availableQualities: [StreamQuality] { get }
    var currentQuality: StreamQuality? { get }
    var latencyPublisher: AnyPublisher<TimeInterval?, Never> { get }
    var adBreakPublisher: AnyPublisher<TimeInterval?, Never> { get }

    func load(_ resolution: PlaybackResolution)
    func play()
    func pause()
    func seekToLive()
    func setQuality(_ quality: StreamQuality)
    func setMuted(_ muted: Bool)
    func teardown()
}
