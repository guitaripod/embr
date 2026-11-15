import UIKit
import EmbrCore
import MidgarCore

extension VideoViewController {
    /// The latency mode a live stream resolves with; every other source plays as it always has.
    var requestedLatency: LiveLatency {
        guard case .live = source else { return .standard }
        #if DEBUG
        if ScreenshotHarness.hyperLatency { return .hyper }
        #endif
        return store.current.liveLatency
    }

    /// A live resolution in the mode Settings asks for now, which a switch made while the resolve was in flight may have
    /// changed; anything else as it came.
    func inLatency(_ resolution: PlaybackResolution, _ latency: LiveLatency) -> PlaybackResolution {
        guard case .live = source else { return resolution }
        return resolution.withLatency(latency)
    }

    /// Moves the live stream to the latency mode Settings now asks for on the same Twitch session, so the switch costs
    /// a moment of buffering instead of a fresh preroll.
    func switchLatency(to latency: LiveLatency) {
        guard case .live = source, latency != playingLatency, let resolution = lastResolution,
              let hls = player as? HLSVideoPlayer, !didTeardownPlayer else { return }
        let next = resolution.withLatency(latency)
        lastResolution = next
        playingLatency = latency
        hls.pinsVariant = latency == .hyper
        overlay.setHyperLatency(latency == .hyper)
        let playing = streamActive && isPlayingOrStarting
        if playing { overlay.setBuffering(true) }
        hls.load(next, playing: playing)
        MidgarLog.info("live latency -> \(latency.rawValue)\(playing ? "" : " (held)")", category: .playback)
    }

    private var isPlayingOrStarting: Bool {
        switch currentState {
        case .playing, .buffering, .loading: true
        case .idle, .paused, .ended, .error: false
        }
    }
}
