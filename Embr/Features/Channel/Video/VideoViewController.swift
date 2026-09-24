import AVKit
import Combine
import MediaPlayer
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
    var onAudioOnlyChanged: ((Bool) -> Void)?
    var onPlaybackStateChanged: ((Bool) -> Void)?

    private let source: VideoSource
    private var player: VideoPlaying
    private let resolver: PlaybackResolving
    private let logger: AppLogger
    private let store: SettingsStore
    private let imageLoader: ImageLoading
    private let feedback = UIImpactFeedbackGenerator(style: .medium)

    private let overlay = VideoOverlayView()
    private var cancellables = Set<AnyCancellable>()
    private var playerCancellables = Set<AnyCancellable>()
    private var triedWebFallback = false
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
    private var didTeardownPlayer = false
    private let nowPlaying = NowPlayingCoordinator()
    private var nowPlayingTitle: String?
    private var nowPlayingChannelName: String?
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var artworkURL: URL?
    private(set) var isAudioOnly = false
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
        imageLoader: ImageLoading = ImageLoader.shared,
        active: Bool = true
    ) {
        self.source = source
        self.player = player
        self.resolver = resolver
        self.logger = logger
        self.store = store
        self.imageLoader = imageLoader
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
        bindPlayer()
        observeLifecycle()
        registerRemoteCommands()
        startPlayback()
    }

    private var isPiPActive = false
    private var pendingAudioOnlyOnPiPStop = false

    private func observeLifecycle() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleForeground),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil
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
        guard !isPiPActive,
              (player as? HLSVideoPlayer)?.isPictureInPictureActive != true else { return }
        if store.current.backgroundAudio == false {
            player.pause()
        } else {
            setLayerAttached(false)
        }
    }

    @objc private func handleWillEnterForeground() {
        reattachLayerIfNeeded()
    }

    private func reattachLayerIfNeeded() {
        guard !isAudioOnly else { return }
        setLayerAttached(true)
    }

    private func setLayerAttached(_ attached: Bool) {
        (player as? HLSVideoPlayer)?.setLayerAttached(attached)
    }

    @objc private func handleForeground() {
        reattachLayerIfNeeded()
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
        if isBeingRemovedFromHierarchy {
            teardownPlayerIfNeeded()
        }
    }

    private var isBeingRemovedFromHierarchy: Bool {
        var ancestor: UIViewController? = self
        while let current = ancestor {
            if current.isMovingFromParent || current.isBeingDismissed { return true }
            ancestor = current.parent
        }
        return false
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
        if !isAudioOnly {
            (player as? HLSVideoPlayer)?.setAudioOnly(false)
            setLayerAttached(true)
        }
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
        let sheet = UIAlertController(title: String(localized: "Playback Speed"), message: nil, preferredStyle: .actionSheet)
        for rate in rates {
            let title = rate == 1.0 ? String(localized: "Normal") : Self.rateText(rate)
            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.applyRate(rate)
            }
            action.setValue(rate == currentRate, forKey: "checked")
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
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
            overlay.setAirPlayHidden(false)
        } else {
            overlay.setPictureInPictureEnabled(false)
            overlay.setAirPlayHidden(true)
        }

        overlay.setSeekable(isSeekableSource)
        overlay.setLive(!isSeekableSource)

        swipeDown.delegate = self
        view.addGestureRecognizer(swipeDown)
    }

    private func bindPlayer() {
        playerCancellables.removeAll()
        player.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.apply(state)
            }
            .store(in: &playerCancellables)

        player.latencyPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] latency in
                self?.overlay.setLatency(latency)
            }
            .store(in: &playerCancellables)

        player.adBreakPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] remaining in
                self?.handleAdBreak(remaining)
            }
            .store(in: &playerCancellables)

        player.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let self else { return }
                self.lastProgress = progress
                self.overlay.setProgress(progress)
            }
            .store(in: &playerCancellables)
    }

    /// Last-resort fallback: when the ad-stripped HLS path can't recover, swap to
    /// the compliant Twitch web embed (anonymous, shows ads, but resilient).
    private func swapToWebPlayer() {
        guard !(player is WebViewPlayer), !triedWebFallback else { return }
        triedWebFallback = true
        recoveryAttempts = 0
        cancelRecoveryTimers()
        logger.info("HLS recovery exhausted — falling back to web player", category: .playback)
        installWebPlayer()
        resolveAndLoad()
    }

    /// Starts playback, first moving a live channel onto the web embed when the Worker's
    /// remote switch says the native path is out of service.
    private func startPlayback() {
        if case .live = source, RemoteConfigService.shared.startsLiveInEmbed, !(player is WebViewPlayer) {
            triedWebFallback = true
            logger.info("remote config routes live playback to the web player", category: .playback)
            installWebPlayer()
        }
        guard streamActive else { return }
        resolveAndLoad()
    }

    private func installWebPlayer() {
        if isAudioOnly { clearAudioOnlyState() }
        let previous = player
        previous.teardown()
        previous.view.removeFromSuperview()

        let web = WebViewPlayer()
        player = web
        let playerView = web.view
        playerView.frame = view.bounds
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(playerView, belowSubview: overlay)
        bindPlayer()

        web.setMuted(isMuted)
        overlay.setPictureInPictureEnabled(false)
        overlay.setAirPlayHidden(true)
        overlay.setMuted(isMuted)
        overlay.clearError()
        overlay.setReconnecting(false)
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
        guard !didTeardownPlayer else { return }
        currentState = state
        if state != .playing { stableWork?.cancel(); stableWork = nil }
        switch state {
        case .loading, .buffering:
            overlay.setBuffering(true)
            startStallWatchdog()
        case .playing:
            showingError = false
            overlay.clearError()
            overlay.setReconnecting(false)
            overlay.setBuffering(false)
            overlay.setPlaying(true)
            recoveryWork?.cancel(); recoveryWork = nil
            stallWork?.cancel(); stallWork = nil
            armStabilityReset()
            applyPendingSeek()
        case .paused:
            overlay.setReconnecting(false)
            overlay.setBuffering(false)
            overlay.setPlaying(false)
            stallWork?.cancel(); stallWork = nil
        case .idle:
            overlay.setReconnecting(false)
            overlay.setBuffering(false)
            overlay.setPlaying(false)
            stallWork?.cancel(); stallWork = nil
        case .ended:
            overlay.setReconnecting(false)
            overlay.setBuffering(false)
            overlay.setPlaying(false)
            stallWork?.cancel(); stallWork = nil
            handleStreamEnded()
        case .error(let message):
            overlay.setReconnecting(false)
            overlay.setBuffering(false)
            overlay.setPlaying(false)
            handlePlaybackError(message)
        }
        updateNowPlaying()
        onPlaybackStateChanged?(state == .playing)
    }

    /// A live source reaching `.ended` means the broadcast stopped (went offline),
    /// not a playback fault — present a calm offline notice, never the error card.
    /// A seekable VOD/clip reaching `.ended` is a normal finish; leave controls be.
    private func handleStreamEnded() {
        guard !showingError else { return }
        switch source {
        case .live(let login):
            cancelRecoveryTimers()
            recoveryAttempts = 0
            showingError = true
            logger.info("live source ended — presenting offline notice", category: .playback)
            overlay.showEnded(String(localized: "\(login) is offline."), symbol: "tv.slash")
        case .vod, .clip:
            break
        }
    }

    func setNowPlayingMetadata(title: String?, channelName: String?, avatarURL: URL? = nil) {
        nowPlayingTitle = title
        nowPlayingChannelName = channelName
        updateNowPlaying()
        loadArtworkIfNeeded(avatarURL)
    }

    private func loadArtworkIfNeeded(_ url: URL?) {
        guard let url, url != artworkURL else { return }
        artworkURL = url
        Task { [weak self, imageLoader] in
            let image = await imageLoader.image(for: url, targetScale: 2.0)
            guard let self, self.artworkURL == url else { return }
            guard let image else {
                self.artworkURL = nil
                return
            }
            self.nowPlayingArtwork = Self.makeArtwork(image)
            self.updateNowPlaying()
        }
    }

    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    func setAudioOnly(_ on: Bool) {
        guard on != isAudioOnly, case .live = source else { return }
        isAudioOnly = on
        if on {
            if isPiPActive {
                pendingAudioOnlyOnPiPStop = true
                (player as? HLSVideoPlayer)?.stopPictureInPicture()
            } else {
                enterAudioOnlyPlayback()
            }
        } else {
            pendingAudioOnlyOnPiPStop = false
            setLayerAttached(true)
            (player as? HLSVideoPlayer)?.setAudioOnly(false)
        }
        logger.info("audio-only \(on ? "enabled" : "disabled")", category: .playback)
        onAudioOnlyChanged?(on)
    }

    private func enterAudioOnlyPlayback() {
        (player as? HLSVideoPlayer)?.setAudioOnly(true)
        setLayerAttached(false)
    }

    func exitAudioOnlyKeepingPlayerVariant() {
        guard isAudioOnly else { return }
        clearAudioOnlyState()
    }

    private func clearAudioOnlyState() {
        isAudioOnly = false
        pendingAudioOnlyOnPiPStop = false
        onAudioOnlyChanged?(false)
    }

    func togglePlayPause() {
        videoOverlayDidTapPlayPause(overlay)
    }

    private var defaultNowPlayingTitle: String {
        switch source {
        case .live(let login): return login
        case .vod: return String(localized: "Video")
        case .clip: return String(localized: "Clip")
        }
    }

    private var defaultNowPlayingArtist: String? {
        if case .live(let login) = source { return login }
        return nil
    }

    private func updateNowPlaying() {
        guard !didTeardownPlayer else { return }
        nowPlaying.update(
            title: nowPlayingTitle ?? defaultNowPlayingTitle,
            artist: nowPlayingChannelName ?? defaultNowPlayingArtist,
            isLive: !isSeekableSource,
            elapsed: lastProgress.current,
            duration: lastProgress.duration,
            isPlaying: currentState == .playing,
            rate: currentRate,
            artwork: nowPlayingArtwork
        )
    }

    private func registerRemoteCommands() {
        nowPlaying.register(
            play: { [weak self] in self?.remotePlay() },
            pause: { [weak self] in self?.player.pause() },
            toggle: { [weak self] in self?.remoteTogglePlayPause() }
        )
    }

    private func remotePlay() {
        if case .live = source { player.seekToLive() }
        player.play()
    }

    private func remoteTogglePlayPause() {
        if currentState == .playing {
            player.pause()
        } else {
            remotePlay()
        }
    }

    private func teardownPlayerIfNeeded() {
        guard !didTeardownPlayer else { return }
        didTeardownPlayer = true
        cancelRecoveryTimers()
        overlay.setReconnecting(false)
        overlay.setBuffering(false)
        nowPlaying.clear()
        player.teardown()
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
            if UIApplication.shared.applicationState != .active {
                let work = DispatchWorkItem { [weak self] in self?.reload(preservingPosition: true, isRecovery: true) }
                recoveryWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 16, execute: work)
                return
            }
            if !triedWebFallback, !(player is WebViewPlayer) {
                swapToWebPlayer()
                return
            }
            showingError = true
            stallWork?.cancel(); stallWork = nil
            overlay.setReconnecting(false)
            player.pause()
            overlay.showError(String(localized: "Playback stopped. Check your connection and try again."), symbol: "exclamationmark.triangle", canRetry: true)
            return
        }
        let delay = min(pow(2.0, Double(recoveryAttempts)), 16)
        recoveryAttempts += 1
        overlay.setBuffering(true)
        overlay.setReconnecting(true)
        let work = DispatchWorkItem { [weak self] in self?.reload(preservingPosition: true, isRecovery: true) }
        recoveryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func reload(preservingPosition: Bool, isRecovery: Bool = false) {
        if !isRecovery { overlay.setReconnecting(false) }
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
        if case .live(let login) = source, let web = player as? WebViewPlayer {
            isResolving = false
            web.loadChannel(login)
            return
        }
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
            showingError = true
            overlay.setReconnecting(false)
            logger.info("resolve: channel offline (\(error.localizedDescription))", category: .playback)
            overlay.setPlaying(false)
            overlay.showEnded(offlineMessage, symbol: "tv.slash")
        } else {
            logger.warn("resolve failed (\(error.localizedDescription)), scheduling recovery", category: .playback)
            overlay.setPlaying(false)
            scheduleRecovery()
        }
    }

    private var offlineMessage: String {
        if case .live(let login) = source { return String(localized: "\(login) isn't live right now.") }
        return String(localized: "This content isn't available right now.")
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
        let sheet = UIAlertController(title: String(localized: "Quality"), message: nil, preferredStyle: .actionSheet)

        sheet.addAction(qualityAction(named: String(localized: "Auto"), quality: autoQuality, isSelected: !isAudioOnly && player.currentQuality == nil))
        for quality in qualities where quality.name.caseInsensitiveCompare("auto") != .orderedSame {
            let selected = quality.isAudioOnly ? isAudioOnly : (!isAudioOnly && player.currentQuality == quality)
            let label = quality.isAudioOnly ? String(localized: "Audio Only") : quality.name
            sheet.addAction(qualityAction(named: label, quality: quality, isSelected: selected))
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))

        if let popover = sheet.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
        }
        present(sheet, animated: true)
    }

    private func qualityAction(named name: String, quality: StreamQuality, isSelected: Bool) -> UIAlertAction {
        let action = UIAlertAction(title: name, style: .default) { [weak self] _ in
            guard let self else { return }
            if quality.isAudioOnly {
                self.setAudioOnly(true)
            } else {
                if self.isAudioOnly { self.setAudioOnly(false) }
                self.player.setQuality(quality)
            }
        }
        action.setValue(isSelected, forKey: "checked")
        return action
    }

    private var autoQuality: StreamQuality {
        StreamQuality(name: "Auto", url: URL(string: "embr://auto")!)
    }

    private func dismissSelf() {
        teardownPlayerIfNeeded()
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
        let restore = {
            self.player.view.center = self.dragStartCenter
            self.overlay.alpha = 1
        }
        if Motion.reduced {
            UIView.animate(withDuration: 0.2, animations: restore)
            return
        }
        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            usingSpringWithDamping: 0.6,
            initialSpringVelocity: 0.8,
            options: [.allowUserInteraction],
            animations: restore
        )
    }

    isolated deinit {
        resolveTask?.cancel()
        adGraceWork?.cancel()
        teardownPlayerIfNeeded()
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
        guard !didTeardownPlayer else { return }
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
        lastProgress = PlaybackProgress(current: seconds, duration: lastProgress.duration, isLive: lastProgress.isLive)
        updateNowPlaying()
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
            lastProgress = PlaybackProgress(current: target, duration: lastProgress.duration, isLive: lastProgress.isLive)
            updateNowPlaying()
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
        overlay.setPictureInPictureActive(true)
        overlay.hideControls()
        setImmersiveState(false)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = false
        overlay.setPictureInPictureActive(false)
        setImmersiveState(view.window?.windowScene?.interfaceOrientation.isLandscape ?? false)
        if pendingAudioOnlyOnPiPStop {
            pendingAudioOnlyOnPiPStop = false
            if isAudioOnly { enterAudioOnlyPlayback() }
        }
        if view.window == nil { teardownPlayerIfNeeded() }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        let host = parent ?? self
        if let presented = host.presentedViewController {
            presented.dismiss(animated: false)
        }
        if let nav = host.navigationController,
           nav.topViewController !== host,
           nav.viewControllers.contains(host) {
            nav.popToViewController(host, animated: false)
        }
        completionHandler(true)
    }
}

@MainActor
private final class NowPlayingCoordinator {
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
