import UIKit
import Combine

enum VideoSource: Sendable, Equatable {
    case live(login: String)
    case vod(id: String)
    case clip(id: String)
}

enum VideoState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case ended
    case error(String)
}

@MainActor
protocol VideoPlaying: AnyObject {
    var view: UIView { get }
    var statePublisher: AnyPublisher<VideoState, Never> { get }

    func load(_ source: VideoSource)
    func play()
    func pause()
    func setMuted(_ muted: Bool)
    func teardown()
}
