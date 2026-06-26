import AVKit
import Combine
import UIKit
import EmbrCore

enum VideoSource: Sendable, Equatable {
    case live(login: String)
    case vod(id: String)
    case clip(url: URL)
}

@MainActor
final class VideoViewController: UIViewController {

    var onDoubleTapToggleChat: (() -> Void)?

    private let source: VideoSource
    private let player: VideoPlaying
    private let resolver: PlaybackResolving
    private let logger: AppLogger
    private let store: SettingsStore
    private let feedback = UIImpactFeedbackGenerator(style: .medium)

    private let overlay = VideoOverlayView()
    private var cancellables = Set<AnyCancellable>()
    private var resolveTask: Task<Void, Never>?

    private var currentState: VideoState = .idle
    private var isImmersive = false
    private var isResolving = false
    private var resolveGeneration = 0
    private var isMuted = false
    private var lastProgress: PlaybackProgress = .empty
    private var currentRate: Float = 1.0
    private var adActive = false
    private var adGraceWork: DispatchWorkItem?

    private var recoveryAttempts = 0
    private var recoveryWork: DispatchWorkItem?
    private var stallWork: DispatchWorkItem?
    private var stableWork: DispatchWorkItem?
    private var refreshWork: DispatchWorkItem?
    private var resumeTarget: TimeInterval?
    private var seekLiveOnReady = false
    private var showingError = false
    private static let maxRecoveryAttempts = 6

    private var isSeekableSource: Bool {
        switch source {
        case .live: return false
        case .vod, .clip: return true
        }
    }

    private var isClipSource: Bool {
        if case .clip = source { return true }
        return false
    }

    private var dragStartCenter: CGPoint = .zero
    private lazy var swipeDown = UIPanGestureRecognizer(target: self, action: #selector(handleSwipeDown(_:)))

    private var streamActive: Bool

    init(
        source: VideoSource,
        player: VideoPlaying = HLSVideoPlayer(),
        resolver: PlaybackResolving = PlaybackResolver.shared,
        logger: AppLogger = .shared,
        store: SettingsStore = .shared,
        active: Bool = true
    ) {
        self.source = source
        self.player = player
        self.resolver = resolver
        self.logger = logger
        self.store = store
        self.streamActive = active
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        [.portrait, .landscapeLeft, .landscapeRight]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        installPlayerView()
        installOverlay()
        bind()
        observeLifecycle()
        if streamActive { resolveAndLoad() }
    }

    private var isPiPActive = false

    private func observeLifecycle() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleForeground),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        NetworkMonitor.shared.restored
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.logger.info("network restored, recovering playback", category: .playback)
                self?.handleForeground()
            }
            .store(in: &cancellables)
    }

    @objc private func handleBackground() {
        guard !store.current.backgroundAudio, !isPiPActive else { return }
        player.pause()
    }

    @objc private func handleForeground() {
        guard streamActive, !isResolving, !showingError else { return }
        switch currentState {
        case .idle, .ended:
            recoveryAttempts = 0
            reload(preservingPosition: true)
        case .buffering:
            if case .live = source { player.seekToLive() }
            player.play()
        case .playing:
            player.play()
        case .paused, .loading, .error:
            break
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        OrientationCoordinator.mask = [.portrait, .landscapeLeft, .landscapeRight]
        UIApplication.shared.isIdleTimerDisabled = store.current.keepScreenAwake
        feedback.prepare()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        OrientationCoordinator.mask = .portrait
        if isLandscape, let scene = view.window?.windowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        player.view.frame = view.bounds
    }

    func setBackButtonHidden(_ hidden: Bool) {
        overlay.setBackButtonHidden(hidden)
    }

    func setStreamActive(_ active: Bool) {
        guard active != streamActive else { return }
        streamActive = active
        guard active else {
            cancelRecoveryTimers()
            player.pause()
            return
        }
        recoveryAttempts = 0
        switch currentState {
        case .idle, .ended, .error:
            resolveAndLoad()
        default:
            player.play()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        })
    }

    private var isLandscape: Bool {
        view.bounds.width > view.bounds.height
    }

    func setImmersiveState(_ immersive: Bool) {
        guard immersive != isImmersive else { return }
        isImmersive = immersive
        overlay.setFullscreen(immersive)
    }

    private func toggleFullscreen() {
        let deviceLandscape = view.window?.windowScene?.interfaceOrientation.isLandscape ?? false
        let goFullscreen = !deviceLandscape
        OrientationCoordinator.mask = goFullscreen ? .landscape : [.portrait, .landscapeLeft, .landscapeRight]
        guard let scene = view.window?.windowScene else { return }
        view.window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        let target: UIInterfaceOrientationMask = goFullscreen ? .landscapeRight : .portrait
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { error in
            AppLogger.shared.warn("fullscreen rotate failed: \(error.localizedDescription)", category: .ui)
        }
    }

    private func presentSpeedPicker(from sourceView: UIView) {
        let rates: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]
        let sheet = UIAlertController(title: "Playback Speed", message: nil, preferredStyle: .actionSheet)
        for rate in rates {
            let title = rate == 1.0 ? "Normal" : Self.rateText(rate)
            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.applyRate(rate)
            }
            action.setValue(rate == currentRate, forKey: "checked")
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        present(sheet, animated: true)
    }

    private func applyRate(_ rate: Float) {
        currentRate = rate
        player.setRate(rate)
        overlay.setSpeed(rate == 1.0 ? nil : Self.rateText(rate))
    }

    private static func rateText(_ rate: Float) -> String {
        rate == rate.rounded() ? String(format: "%.0fx", rate) : String(format: "%gx", rate)
    }

    private func installPlayerView() {
        let playerView = player.view
        playerView.frame = view.bounds
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(playerView)
    }

    private func installOverlay() {
        overlay.delegate = self
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        if let hls = player as? HLSVideoPlayer {
            hls.pictureInPictureDelegate = self
            overlay.setPictureInPictureEnabled(AVPictureInPictureController.isPictureInPictureSupported())
        } else {
            overlay.setPictureInPictureEnabled(false)
        }

        overlay.setSeekable(isSeekableSource)
        overlay.setLive(!isSeekableSource)

        swipeDown.delegate = self
        view.addGestureRecognizer(swipeDown)
    }

    private func bind() {
        player.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.apply(state)
            }
            .store(in: &cancellables)

        player.latencyPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] latency in
                self?.overlay.setLatency(latency)
            }
            .store(in: &cancellables)

        player.adBreakPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] remaining in
                self?.handleAdBreak(remaining)
            }
            .store(in: &cancellables)

        player.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let self else { return }
                self.lastProgress = progress
                self.overlay.setProgress(progress)
            }
            .store(in: &cancellables)
    }

    private func handleAdBreak(_ remaining: TimeInterval?) {
        if let remaining {
            adGraceWork?.cancel()
            adGraceWork = nil
            overlay.updateAdCountdown(remaining)
            if !adActive {
                adActive = true
                player.setMuted(true)
                overlay.setMuted(true)
                logger.info("ad break started", category: .playback)
            }
        } else if adActive, adGraceWork == nil {
            let work = DispatchWorkItem { [weak self] in self?.endAdSession() }
            adGraceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
        }
    }

    private func endAdSession() {
        adGraceWork = nil
        guard adActive else { return }
        adActive = false
        overlay.updateAdCountdown(nil)
        player.setMuted(isMuted)
        overlay.setMuted(isMuted)
        logger.info("ad break ended", category: .playback)
        if case .live = source { player.seekToLive() }
    }

    private func apply(_ state: VideoState) {
        currentState = state
        if state != .playing { stableWork?.cancel(); stableWork = nil }
        switch state {
        case .loading, .buffering:
            overlay.setBuffering(true)
            startStallWatchdog()
        case .playing:
            showingError = false
            overlay.clearError()
            overlay.setBuffering(false)
            overlay.setPlaying(true)
            recoveryWork?.cancel(); recoveryWork = nil
            stallWork?.cancel(); stallWork = nil
            armStabilityReset()
            applyPendingSeek()
        case .paused:
            overlay.setBuffering(false)
            overlay.setPlaying(false)
            stallWork?.cancel(); stallWork = nil
        case .idle, .ended:
            overlay.setBuffering(false)
            overlay.setPlaying(false)
            stallWork?.cancel(); stallWork = nil
        case .error(let message):
            overlay.setBuffering(false)
            overlay.setPlaying(false)
            handlePlaybackError(message)
        }
    }

    /// Reset the recovery budget only after sustained playback, so a stream that
    /// flaps .playing→.error every second walks up to the cap instead of resetting
    /// the counter each blip and reloading forever.
    private func armStabilityReset() {
        stableWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.recoveryAttempts = 0 }
        stableWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    private func applyPendingSeek() {
        if let target = resumeTarget {
            resumeTarget = nil
            if isSeekableSource { player.seek(to: target) }
        }
        if seekLiveOnReady {
            seekLiveOnReady = false
            if case .live = source { player.seekToLive() }
        }
    }

    private func handlePlaybackError(_ message: String) {
        guard !isResolving else { return }
        if adActive {
            logger.info("ad-break reload: \(message)", category: .playback)
            reload(preservingPosition: false)
            return
        }
        logger.warn("playback error, scheduling recovery: \(message)", category: .playback)
        scheduleRecovery()
    }

    /// Bounded exponential-backoff recovery: re-resolve and reload, escalating the
    /// delay each attempt, and only surfacing the manual error card after the cap —
    /// so a transient blip self-heals instead of parking the user on an error.
    private func scheduleRecovery() {
        guard streamActive, !isResolving, !adActive else { return }
        recoveryWork?.cancel()
        guard recoveryAttempts < Self.maxRecoveryAttempts else {
            showingError = true
            stallWork?.cancel(); stallWork = nil
            player.pause()
            overlay.showError("Playback stopped.", symbol: "exclamationmark.triangle", canRetry: true)
            return
        }
        let delay = min(pow(2.0, Double(recoveryAttempts)), 16)
        recoveryAttempts += 1
        overlay.setBuffering(true)
        let work = DispatchWorkItem { [weak self] in self?.reload(preservingPosition: true) }
        recoveryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func reload(preservingPosition: Bool) {
        if preservingPosition, isSeekableSource, lastProgress.current > 0 {
            resumeTarget = lastProgress.current
        }
        if case .live = source { seekLiveOnReady = true }
        resolveAndLoad()
    }

    private func startStallWatchdog() {
        guard !adActive, !showingError else { return }
        stallWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.handleStall() }
        stallWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    private func handleStall() {
        stallWork = nil
        guard streamActive, !isResolving, !adActive else { return }
        switch currentState {
        case .buffering, .loading:
            logger.warn("stall watchdog fired after 15s buffering", category: .playback)
            scheduleRecovery()
        default:
            break
        }
    }

    private func scheduleTokenRefresh(_ expiresAt: Date?) {
        refreshWork?.cancel()
        refreshWork = nil
        guard !isClipSource else { return }
        let interval: TimeInterval = expiresAt.map { max(60, $0.timeIntervalSinceNow - 120) } ?? (50 * 60)
        let work = DispatchWorkItem { [weak self] in
            self?.logger.info("playback token nearing expiry, re-resolving", category: .playback)
            self?.reload(preservingPosition: true)
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
    }

    private func cancelRecoveryTimers() {
        recoveryWork?.cancel(); recoveryWork = nil
        stallWork?.cancel(); stallWork = nil
        stableWork?.cancel(); stableWork = nil
        refreshWork?.cancel(); refreshWork = nil
        resumeTarget = nil
        seekLiveOnReady = false
    }

    private func resolveAndLoad() {
        resolveTask?.cancel()
        overlay.clearError()
        overlay.setBuffering(true)
        isResolving = true
        resolveGeneration += 1
        let generation = resolveGeneration
        resolveTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolution = try await self.resolve()
                if Task.isCancelled || generation != self.resolveGeneration { return }
                self.isResolving = false
                self.player.load(resolution)
                self.scheduleTokenRefresh(resolution.expiresAt)
            } catch {
                if Task.isCancelled || generation != self.resolveGeneration { return }
                self.isResolving = false
                self.handleResolveFailure(error)
            }
        }
    }

    private func handleResolveFailure(_ error: Error) {
        let apiError = error as? APIError
        if apiError == .notFound || apiError == .forbidden {
            recoveryAttempts = 0
            recoveryWork?.cancel(); recoveryWork = nil
            logger.info("resolve: channel offline (\(error.localizedDescription))", category: .playback)
            overlay.setPlaying(false)
            overlay.showError("This channel isn't live right now.", symbol: "tv.slash", canRetry: true)
        } else {
            logger.warn("resolve failed (\(error.localizedDescription)), scheduling recovery", category: .playback)
            overlay.setPlaying(false)
            scheduleRecovery()
        }
    }

    private func resolve() async throws -> PlaybackResolution {
        switch source {
        case .live(let login):
            return try await resolver.resolveLive(channelLogin: login)
        case .vod(let id):
            return try await resolver.resolveVOD(videoID: id)
        case .clip(let url):
            return PlaybackResolution(masterPlaylistURL: url, qualities: [], expiresAt: nil)
        }
    }

    private func presentQualityPicker(from sourceView: UIView) {
        let qualities = player.availableQualities
        let sheet = UIAlertController(title: "Quality", message: nil, preferredStyle: .actionSheet)

        sheet.addAction(qualityAction(named: "Auto", quality: autoQuality, isSelected: player.currentQuality == nil))
        for quality in qualities where quality.name.caseInsensitiveCompare("auto") != .orderedSame {
            sheet.addAction(qualityAction(named: quality.name, quality: quality, isSelected: player.currentQuality == quality))
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        present(sheet, animated: true)
    }

    private func qualityAction(named name: String, quality: StreamQuality, isSelected: Bool) -> UIAlertAction {
        let action = UIAlertAction(title: name, style: .default) { [weak self] _ in
            self?.player.setQuality(quality)
        }
        action.setValue(isSelected, forKey: "checked")
        return action
    }

    private var autoQuality: StreamQuality {
        StreamQuality(name: "Auto", url: URL(string: "embr://auto")!)
    }

    private func dismissSelf() {
        player.teardown()
        if let navigationController, navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    @objc private func handleSwipeDown(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: view)
        switch recognizer.state {
        case .began:
            dragStartCenter = player.view.center
            feedback.prepare()
        case .changed:
            guard translation.y > 0 else { return }
            let damped = translation.y * 0.55
            player.view.center = CGPoint(x: dragStartCenter.x, y: dragStartCenter.y + damped)
            let progress = min(1, translation.y / 240)
            overlay.alpha = 1 - progress
        case .ended, .cancelled:
            let velocity = recognizer.velocity(in: view).y
            if translation.y > 120 || velocity > 800 {
                triggerPictureInPicture()
            }
            springBack()
        default:
            break
        }
    }

    private func triggerPictureInPicture() {
        feedback.impactOccurred()
        if let hls = player as? HLSVideoPlayer, hls.canStartPictureInPicture {
            hls.startPictureInPicture()
        }
    }

    private func springBack() {
        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0.8,
            options: [.allowUserInteraction],
            animations: {
                self.player.view.center = self.dragStartCenter
                self.overlay.alpha = 1
            }
        )
    }

    isolated deinit {
        resolveTask?.cancel()
        cancelRecoveryTimers()
        adGraceWork?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}

extension VideoViewController: VideoOverlayViewDelegate {
    func videoOverlayDidTapBack(_ overlay: VideoOverlayView) {
        dismissSelf()
    }

    func videoOverlayDidTapPlayPause(_ overlay: VideoOverlayView) {
        switch currentState {
        case .playing, .buffering, .loading:
            player.pause()
        case .ended where isSeekableSource:
            player.seek(to: 0)
            player.play()
        default:
            if case .live = source { player.seekToLive() }
            player.play()
        }
    }

    func videoOverlayDidTapQuality(_ overlay: VideoOverlayView, from sourceView: UIView) {
        presentQualityPicker(from: sourceView)
    }

    func videoOverlayDidTapPictureInPicture(_ overlay: VideoOverlayView) {
        triggerPictureInPicture()
    }

    func videoOverlayDidTapRetry(_ overlay: VideoOverlayView) {
        showingError = false
        recoveryAttempts = 0
        resolveAndLoad()
    }

    func videoOverlayDidTapMute(_ overlay: VideoOverlayView) {
        isMuted.toggle()
        player.setMuted(isMuted)
        overlay.setMuted(isMuted)
    }

    func videoOverlayDidTapFullscreen(_ overlay: VideoOverlayView) {
        toggleFullscreen()
    }

    func videoOverlayDidTapAdInfo(_ overlay: VideoOverlayView) {
        present(AdInfoViewController(), animated: true)
    }

    func videoOverlayDidTapSpeed(_ overlay: VideoOverlayView, from sourceView: UIView) {
        presentSpeedPicker(from: sourceView)
    }

    func videoOverlayDidBeginScrubbing(_ overlay: VideoOverlayView) {}

    func videoOverlay(_ overlay: VideoOverlayView, didCommitScrubTo seconds: TimeInterval) {
        resumeTarget = nil
        player.seek(to: seconds)
    }

    func videoOverlay(_ overlay: VideoOverlayView, didDoubleTapForward forward: Bool) {
        let landscape = view.window?.windowScene?.interfaceOrientation.isLandscape ?? false
        if landscape, let onDoubleTapToggleChat {
            onDoubleTapToggleChat()
            return
        }
        if isSeekableSource {
            resumeTarget = nil
            let delta: TimeInterval = forward ? 10 : -10
            let target = max(0, min(lastProgress.current + delta, lastProgress.duration > 0 ? lastProgress.duration : .greatestFiniteMagnitude))
            player.seek(to: target)
            overlay.flashSeek(seconds: 10, forward: forward)
        } else {
            overlay.toggleControls()
        }
    }
}

extension VideoViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === swipeDown else { return true }
        let velocity = swipeDown.velocity(in: view)
        return abs(velocity.y) > abs(velocity.x)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === swipeDown else { return true }
        return !overlay.isScrubberTouch(touch)
    }
}

extension VideoViewController: @MainActor AVPictureInPictureControllerDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        logger.error("PiP failed: \(error.localizedDescription)", category: .playback)
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = true
        overlay.hideControls()
        setImmersiveState(false)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = false
        setImmersiveState(view.window?.windowScene?.interfaceOrientation.isLandscape ?? false)
    }
}
