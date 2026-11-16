import UIKit
import EmbrCore
import MidgarCore

extension VideoViewController {
    /// The latency mode Settings asks for: Hyper only for a Founding Member who turned it on; every other source plays
    /// as it always has.
    var requestedLatency: LiveLatency {
        guard case .live = source else { return .standard }
        #if DEBUG
        if ScreenshotHarness.hyperLatency { return .hyper }
        #endif
        return store.current.hyperLowLatencyEnabled && SupporterStore.shared.isSupporter ? .hyper : .standard
    }

    /// Whether a live resolve proves the Founding Member purchase, so the session comes with its Hyper link whether or
    /// not Hyper is on, and turning it on later keeps the session.
    var wantsHyperLink: Bool {
        guard case .live = source else { return false }
        return SupporterStore.shared.isSupporter
    }

    /// The mode a resolution plays in now: Hyper when Settings asks for it and the worker handed over the link, which
    /// it does only for a verified Founding Member while Hyper is switched on, and never while the audio goes to a TV,
    /// since Hyper's on-device playlists cannot be handed to one.
    func effectiveLatency(for resolution: PlaybackResolution) -> LiveLatency {
        guard requestedLatency == .hyper, (player as? HLSVideoPlayer)?.routesToTV != true else { return .standard }
        #if DEBUG
        if ScreenshotHarness.hyperLatency { return .hyper }
        #endif
        return resolution.offersHyper ? .hyper : .standard
    }

    /// A live resolution in the mode Settings asks for now, which a switch made while the resolve was in flight may have
    /// changed; anything else as it came.
    func inLatency(_ resolution: PlaybackResolution, _ latency: LiveLatency) -> PlaybackResolution {
        guard case .live = source else { return resolution }
        return resolution.withLatency(latency)
    }

    /// Moves the live stream to the latency mode Settings now asks for on the same Twitch session, so the switch costs
    /// a moment of buffering instead of a fresh preroll.
    func switchLatency(to requested: LiveLatency) {
        guard case .live = source, let resolution = lastResolution,
              let hls = player as? HLSVideoPlayer, !didTeardownPlayer else { return }
        if requested == .hyper, !resolution.offersHyper, wantsHyperLink, (player as? HLSVideoPlayer)?.routesToTV != true {
            resolveAgainForHyper()
            return
        }
        let latency = effectiveLatency(for: resolution)
        guard latency != playingLatency else { return }
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
