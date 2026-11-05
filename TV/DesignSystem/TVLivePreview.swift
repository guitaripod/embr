import AVFoundation
import UIKit
import EmbrCore
import MidgarCore

/// The muted live preview a stream card plays after it has held focus for a moment, like hovering a stream on the
/// web. One player serves the whole app, capped at a small rendition, and it moves to whichever card is focused. It
/// stays off when the person turned previews off in Settings or turned off video autoplay for the whole Apple TV.
@MainActor
final class TVLivePreview {
    static let shared = TVLivePreview()

    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()
    private weak var host: TVStreamCell?
    private var pending: Task<Void, Never>?
    private var readyObservation: NSKeyValueObservation?
    private var resolutions: [String: (resolution: PlaybackResolution, at: Date)] = [:]

    private static let resolutionLifetime: TimeInterval = 60

    private init() {
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.opacity = 0
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            let ready = layer.isReadyForDisplay
            Task { @MainActor in self?.reveal(ready) }
        }
    }

    private var isAllowed: Bool {
        SettingsStore.shared.current.livePreviewsEnabled && UIAccessibility.isVideoAutoplayEnabled
    }

    /// Starts the preview in `cell` after the focus delay, unless focus has moved on by then.
    func focus(_ cell: TVStreamCell) {
        guard isAllowed, let stream = cell.stream else { return }
        pending?.cancel()
        if host !== cell { stop() }
        let login = stream.userLogin
        pending = Task { [weak self, weak cell] in
            try? await Task.sleep(for: .seconds(TVMetrics.previewDelay))
            guard !Task.isCancelled, let self, let cell, cell.stream?.userLogin == login else { return }
            await self.play(login: login, in: cell)
        }
    }

    func detach(from cell: TVStreamCell) {
        guard host === cell else { return }
        stop()
    }

    func stop() {
        pending?.cancel()
        pending = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        playerLayer.opacity = 0
        playerLayer.removeFromSuperlayer()
        host = nil
    }

    private func play(login: String, in cell: TVStreamCell) async {
        guard let resolution = await resolution(for: login), !Task.isCancelled, cell.stream?.userLogin == login else { return }
        let item = AVPlayerItem(url: resolution.masterPlaylistURL)
        item.preferredMaximumResolution = CGSize(width: 960, height: 540)
        item.preferredPeakBitRate = 1_800_000
        item.preferredForwardBufferDuration = 2
        host = cell
        playerLayer.opacity = 0
        playerLayer.frame = cell.previewContainer.bounds
        cell.previewContainer.layer.addSublayer(playerLayer)
        player.replaceCurrentItem(with: item)
        player.play()
        MidgarLog.debug("preview started for \(login)", category: .playback)
    }

    private func reveal(_ ready: Bool) {
        guard ready, host != nil else { return }
        if let container = host?.previewContainer {
            playerLayer.frame = container.bounds
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.4
        playerLayer.add(fade, forKey: "fade")
        playerLayer.opacity = 1
    }

    private func resolution(for login: String) async -> PlaybackResolution? {
        if let cached = resolutions[login], Date().timeIntervalSince(cached.at) < Self.resolutionLifetime {
            return cached.resolution
        }
        do {
            let resolution = try await AppContainer.shared.playback.resolveLive(channelLogin: login)
            resolutions[login] = (resolution, Date())
            return resolution
        } catch {
            MidgarLog.debug("preview resolve failed for \(login): \(error)", category: .playback)
            return nil
        }
    }
}
