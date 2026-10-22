import AVKit
import Combine
import MediaPlayer
import UIKit
import EmbrCore
import MidgarCore

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
    /// Set by a hosting channel page: on iPad the fullscreen button changes that page's layout
    /// instead of rotating the device.
    var onToggleFullscreen: (() -> Void)?
    /// The hosting page's current fullscreen state, restored when Picture in Picture ends.
    var hostImmersiveState: (() -> Bool)?

    let source: VideoSource
    var player: VideoPlaying
    private let resolver: PlaybackResolving
    private let store: SettingsStore
    let imageLoader: ImageLoading
    private let feedback = UIImpactFeedbackGenerator(style: .medium)

    let overlay = VideoOverlayView()
    private var cancellables = Set<AnyCancellable>()
    private var playerCancellables = Set<AnyCancellable>()
    private var triedWebFallback = false
    private var resolveTask: Task<Void, Never>?

    var currentState: VideoState = .idle
    var isImmersive = false
    private var isResolving = false
    private var resolveGeneration = 0
    var isMuted = false
    var lastProgress: PlaybackProgress = .empty
    var currentRate: Float = 1.0
    private var adActive = false
    private var adGraceWork: DispatchWorkItem?

    var recoveryAttempts = 0
    private var recoveryWork: DispatchWorkItem?
    private var stallWork: DispatchWorkItem?
    private var stableWork: DispatchWorkItem?
    private var refreshWork: DispatchWorkItem?
    var resumeTarget: TimeInterval?
    private var seekLiveOnReady = false
    var showingError = false
    var didTeardownPlayer = false
    let nowPlaying = NowPlayingCoordinator()
    var nowPlayingTitle: String?
    var nowPlayingChannelName: String?
    var nowPlayingArtwork: MPMediaItemArtwork?
    var artworkURL: URL?
    private(set) var isAudioOnly = false
    private static let maxRecoveryAttempts = 6

    var isSeekableSource: Bool {
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
    lazy var swipeDown = UIPanGestureRecognizer(target: self, action: #selector(handleSwipeDown(_:)))

    private var streamActive: Bool

    init(
        source: VideoSource,
        player: VideoPlaying = VideoViewController.makeDefaultPlayer(),
        resolver: PlaybackResolving = PlaybackResolver.shared,
        store: SettingsStore = .shared,
        imageLoader: ImageLoading = ImageLoader.shared,
        active: Bool = true
    ) {
        self.source = source
        self.player = player
        self.resolver = resolver
        self.store = store
        self.imageLoader = imageLoader
        self.streamActive = active
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    static func makeDefaultPlayer() -> VideoPlaying {
        #if DEBUG
        if DemoWorld.isActive { return DemoVideoPlayer() }
        #endif
        return HLSVideoPlayer()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        OrientationCoordinator.isPhone ? [.portrait, .landscapeLeft, .landscapeRight] : .all
    }

    override var prefersStatusBarHidden: Bool { isStandaloneFullscreen }
    override var prefersHomeIndicatorAutoHidden: Bool { isStandaloneFullscreen }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        Fold.relayout(view)
        installPlayerView()
        installOverlay()
        bindPlayer()
        observeLifecycle()
        registerRemoteCommands()
        startPlayback()
    }

    var isPiPActive = false
    var pendingAudioOnlyOnPiPStop = false

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
                MidgarLog.info("network restored, recovering playback", category: .playback)
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
        if isStandalone {
            (tabBarController as? RootTabBarController)?.beginPlayback()
        }
        OrientationCoordinator.phoneMask = [.portrait, .landscapeLeft, .landscapeRight]
        UIApplication.shared.isIdleTimerDisabled = store.current.keepScreenAwake
        feedback.prepare()
    }

    /// The window only knows which orientations a video allows once this page is on screen, so it
    /// is asked again here; until then it keeps the portrait-only answer it was given while browsing.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        OrientationCoordinator.phoneMask = .portrait
        if !usesTabletLayout, isLandscape, let scene = view.window?.windowScene {
            OrientationCoordinator.rotate(scene, to: .portrait)
        }
        if isStandaloneFullscreen {
            isStandaloneFullscreen = false
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
        if isStandalone, isMovingFromParent {
            (tabBarController as? RootTabBarController)?.endPlayback()
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
        player.view.frame = playerFrame
    }

    /// A video that has the page to itself sits in the top region while the device is folded like a
    /// laptop, so the picture stays off the crease and the controls on the overlay keep to the
    /// stable half below it.
    private var playerFrame: CGRect {
        guard isStandalone, !isStandaloneFullscreen, case .horizontal(let minY, _)? = Fold.region(in: view),
              minY > view.bounds.height / 4 else { return view.bounds }
        return CGRect(x: 0, y: 0, width: view.bounds.width, height: minY)
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

    /// Judged on the window, not on this view, which may be a small player inside a page.
    private var usesTabletLayout: Bool {
        OrientationCoordinator.usesTabletLayout(for: view.window?.bounds.size ?? view.bounds.size)
    }

    func setImmersiveState(_ immersive: Bool) {
        guard immersive != isImmersive else { return }
        isImmersive = immersive
        overlay.setFullscreen(immersive)
    }

    /// The phone goes fullscreen by turning to landscape. An iPad window cannot be rotated from
    /// inside, so there the hosting channel page (or, for a video pushed on its own, this
    /// controller) hides its chrome instead.
    func toggleFullscreen() {
        guard !usesTabletLayout else {
            if let onToggleFullscreen {
                onToggleFullscreen()
            } else {
                setStandaloneFullscreen(!isStandaloneFullscreen)
            }
            return
        }
        let goFullscreen = !OrientationCoordinator.isLandscape(view.window?.windowScene)
        OrientationCoordinator.phoneMask = goFullscreen ? .landscape : [.portrait, .landscapeLeft, .landscapeRight]
        guard let scene = view.window?.windowScene else { return }
        view.window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        let target: UIInterfaceOrientationMask = goFullscreen ? .landscapeRight : .portrait
        OrientationCoordinator.rotate(scene, to: target) { error in
            MidgarLog.notice("fullscreen rotate failed: \(error.localizedDescription)", category: .ui)
        }
    }

    private(set) var isStandaloneFullscreen = false

    /// Pushed on its own (a past broadcast or clip) rather than embedded in a channel page.
    private var isStandalone: Bool {
        parent is UINavigationController
    }

    /// Fullscreen for a video pushed on its own on iPad: the navigation bar and status bar go,
    /// and the video fills the window.
    func setStandaloneFullscreen(_ fullscreen: Bool) {
        guard fullscreen != isStandaloneFullscreen else { return }
        isStandaloneFullscreen = fullscreen
        navigationController?.setNavigationBarHidden(fullscreen, animated: true)
        setImmersiveState(fullscreen)
        UIView.animate(withDuration: 0.25) {
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    var restoredStandaloneImmersiveState: Bool {
        guard !usesTabletLayout else { return isStandaloneFullscreen }
        return OrientationCoordinator.isLandscape(view.window?.windowScene)
    }

    var isPlaying: Bool { currentState == .playing }

    var isSeekable: Bool { isSeekableSource }

    /// Jumps a past broadcast or clip by `seconds`, clamped to its length.
    func skip(by seconds: TimeInterval) {
        guard isSeekableSource else { return }
        resumeTarget = nil
        let end = lastProgress.duration > 0 ? lastProgress.duration : .greatestFiniteMagnitude
        let target = max(0, min(lastProgress.current + seconds, end))
        player.seek(to: target)
        overlay.flashSeek(seconds: Int(abs(seconds)), forward: seconds > 0)
        lastProgress = PlaybackProgress(current: target, duration: lastProgress.duration, isLive: lastProgress.isLive)
        updateNowPlaying()
    }

    func toggleMute() {
        videoOverlayDidTapMute(overlay)
    }

    func presentSpeedPicker(from sourceView: UIView) {
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
        MidgarLog.info("HLS recovery exhausted — falling back to web player", category: .playback)
        installWebPlayer()
        resolveAndLoad()
    }

    /// Starts playback, first moving a live channel onto the web embed when the Worker's
    /// remote switch says the native path is out of service.
    private func startPlayback() {
        if case .live = source, RemoteConfigService.shared.startsLiveInEmbed, !(player is WebViewPlayer) {
            triedWebFallback = true
            MidgarLog.info("remote config routes live playback to the web player", category: .playback)
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
        #if DEBUG
        if ScreenshotHarness.isPosing { return }
        #endif
        if let remaining {
            adGraceWork?.cancel()
            adGraceWork = nil
            overlay.updateAdCountdown(remaining)
            if !adActive {
                adActive = true
                player.setMuted(true)
                overlay.setMuted(true)
                MidgarLog.info("ad break started", category: .playback)
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
        MidgarLog.info("ad break ended", category: .playback)
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
            MidgarLog.info("live source ended — presenting offline notice", category: .playback)
            overlay.showEnded(String(localized: "\(login) is offline."), symbol: "tv.slash")
        case .vod, .clip:
            break
        }
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
        MidgarLog.info("audio-only \(on ? "enabled" : "disabled")", category: .playback)
        onAudioOnlyChanged?(on)
    }

    func enterAudioOnlyPlayback() {
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

    func teardownPlayerIfNeeded() {
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
            MidgarLog.info("ad-break reload: \(message)", category: .playback)
            reload(preservingPosition: false)
            return
        }
        MidgarLog.notice("playback error, scheduling recovery: \(message)", category: .playback)
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
            MidgarLog.notice("stall watchdog fired after 15s buffering", category: .playback)
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
            MidgarLog.info("playback token nearing expiry, re-resolving", category: .playback)
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

    func resolveAndLoad() {
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
            MidgarLog.info("resolve: channel offline (\(error.localizedDescription))", category: .playback)
            overlay.setPlaying(false)
            overlay.showEnded(offlineMessage, symbol: "tv.slash")
        } else {
            MidgarLog.notice("resolve failed (\(error.localizedDescription)), scheduling recovery", category: .playback)
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

    func presentQualityPicker(from sourceView: UIView) {
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

    func dismissSelf() {
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

    func triggerPictureInPicture() {
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
