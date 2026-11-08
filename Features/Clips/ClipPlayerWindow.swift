import AVFoundation
import Combine
import EmbrCore
import MidgarCore

/// The players behind the clip feed. Only the clip on screen and its neighbours hold a player, so swiping lands on a
/// clip that is already buffering and memory stays at three short MP4s however long the feed gets. The clip on screen
/// loops; the others wait paused on their first frame.
@MainActor
final class ClipPlayerWindow {
    struct Progress: Equatable {
        let clipID: String
        let fraction: Double
    }

    /// The clip on screen's position, about 20 times a second while it plays.
    let progress = PassthroughSubject<Progress, Never>()
    /// A clip whose item failed to load, so its cell can offer a retry.
    let failed = PassthroughSubject<String, Never>()

    private final class Slot {
        let player: AVPlayer
        let url: URL
        var endObserver: NSObjectProtocol?
        var statusObservation: NSKeyValueObservation?

        init(url: URL) {
            self.url = url
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 4
            player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = false
            player.actionAtItemEnd = .pause
        }
    }

    private var slots: [String: Slot] = [:]
    private var activeID: String?
    private var timeObserver: Any?
    private var timeObserverOwner: AVPlayer?
    private(set) var isMuted: Bool
    private var userPaused = false

    private static let mutedKey = "clips.feed.muted"

    init(defaults: UserDefaults = .standard) {
        isMuted = defaults.bool(forKey: Self.mutedKey)
    }

    /// The player for a clip, made the first time it is asked for with a URL.
    func player(for clipID: String, url: URL) -> AVPlayer {
        if let slot = slots[clipID], slot.url == url { return slot.player }
        discard(clipID)
        let slot = Slot(url: url)
        slot.player.isMuted = isMuted
        slot.endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: slot.player.currentItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.loop(clipID) }
        }
        slot.statusObservation = slot.player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let reason = item.error.map { "\($0)" } ?? "unknown"
            Task { @MainActor in
                MidgarLog.notice("clip \(clipID) failed to load: \(reason)", category: .playback)
                self?.failed.send(clipID)
            }
        }
        slots[clipID] = slot
        return slot.player
    }

    /// The player already made for a clip, if any.
    func existingPlayer(for clipID: String) -> AVPlayer? {
        slots[clipID]?.player
    }

    /// Makes `clipID` the clip on screen: it plays unless the viewer paused, every other clip pauses at its start.
    func activate(_ clipID: String) {
        guard activeID != clipID else {
            resumeIfAllowed()
            return
        }
        if let previous = activeID, let slot = slots[previous] {
            slot.player.pause()
            slot.player.seek(to: .zero)
        }
        activeID = clipID
        userPaused = false
        observeTime()
        resumeIfAllowed()
    }

    /// Keeps players only for `clipIDs`, the clip on screen and its neighbours.
    func keep(only clipIDs: Set<String>) {
        for clipID in slots.keys where !clipIDs.contains(clipID) {
            discard(clipID)
        }
    }

    var isPlaying: Bool {
        guard let activeID, let player = slots[activeID]?.player else { return false }
        return player.timeControlStatus != .paused
    }

    /// Pauses or resumes the clip on screen by the viewer's choice.
    func togglePlayback() {
        guard let activeID, let player = slots[activeID]?.player else { return }
        if player.timeControlStatus == .paused {
            userPaused = false
            player.play()
        } else {
            userPaused = true
            player.pause()
        }
    }

    /// Pauses everything for a reason that isn't the viewer's choice: the feed left the screen or the app went away.
    func suspend() {
        slots.values.forEach { $0.player.pause() }
    }

    /// Plays the clip on screen again after `suspend()`, unless the viewer had paused it.
    func resumeIfAllowed() {
        guard !userPaused, let activeID, let player = slots[activeID]?.player else { return }
        player.play()
    }

    func setMuted(_ muted: Bool, defaults: UserDefaults = .standard) {
        isMuted = muted
        defaults.set(muted, forKey: Self.mutedKey)
        slots.values.forEach { $0.player.isMuted = muted }
    }

    /// Moves the clip on screen to `fraction` of its length.
    func seek(_ clipID: String, to fraction: Double) {
        guard let player = slots[clipID]?.player, let item = player.currentItem else { return }
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { return }
        let target = CMTime(seconds: duration * min(max(fraction, 0), 1), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func tearDown() {
        removeTimeObserver()
        for clipID in Array(slots.keys) { discard(clipID) }
        activeID = nil
    }

    private func loop(_ clipID: String) {
        guard let player = slots[clipID]?.player else { return }
        player.seek(to: .zero)
        if clipID == activeID, !userPaused { player.play() }
    }

    private func discard(_ clipID: String) {
        guard let slot = slots.removeValue(forKey: clipID) else { return }
        if let endObserver = slot.endObserver { NotificationCenter.default.removeObserver(endObserver) }
        slot.statusObservation?.invalidate()
        if timeObserverOwner === slot.player { removeTimeObserver() }
        slot.player.pause()
        slot.player.replaceCurrentItem(with: nil)
    }

    private func observeTime() {
        removeTimeObserver()
        guard let activeID, let player = slots[activeID]?.player else { return }
        let interval = CMTime(value: 1, timescale: 20)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let duration = self.slots[activeID]?.player.currentItem?.duration.seconds,
                      duration.isFinite, duration > 0 else { return }
                self.progress.send(Progress(clipID: activeID, fraction: min(max(time.seconds / duration, 0), 1)))
            }
        }
        timeObserverOwner = player
    }

    private func removeTimeObserver() {
        if let timeObserver, let owner = timeObserverOwner {
            owner.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        timeObserverOwner = nil
    }
}
