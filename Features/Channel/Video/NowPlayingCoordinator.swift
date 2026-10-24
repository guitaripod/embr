import MediaPlayer
import UIKit

@MainActor
final class NowPlayingCoordinator {
    private var commandTargets: [(MPRemoteCommand, Any)] = []

    func register(
        play: @escaping @MainActor () -> Void,
        pause: @escaping @MainActor () -> Void,
        toggle: @escaping @MainActor () -> Void
    ) {
        guard commandTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        add(center.playCommand, handler: play)
        add(center.pauseCommand, handler: pause)
        add(center.togglePlayPauseCommand, handler: toggle)
    }

    private func add(_ command: MPRemoteCommand, handler: @escaping @MainActor () -> Void) {
        command.isEnabled = true
        let target = command.addTarget { _ in
            MainActor.assumeIsolated { handler() }
            return .success
        }
        commandTargets.append((command, target))
    }

    func update(
        title: String,
        artist: String?,
        isLive: Bool,
        elapsed: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool,
        rate: Float,
        artwork: MPMediaItemArtwork?
    ) {
        var info: [String: Any] = [MPMediaItemPropertyTitle: title]
        if let artist { info[MPMediaItemPropertyArtist] = artist }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        info[MPNowPlayingInfoPropertyIsLiveStream] = isLive
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(rate) : 0.0
        if !isLive, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        commandTargets.forEach { $0.0.removeTarget($0.1) }
        commandTargets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
