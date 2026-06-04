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

    var onFullscreenChange: ((Bool) -> Void)?

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
    private var liveReloadAttempts = 0
    private var isResolving = false
    private var resolveGeneration = 0
    private var isMuted = false

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
        if streamActive { resolveAndLoad() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = store.current.keepScreenAwake
        feedback.prepare()
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
            player.pause()
            return
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
        setImmersive(size.width > size.height)
    }

    private var isLandscape: Bool {
        view.bounds.width > view.bounds.height
    }

    private func setImmersive(_ immersive: Bool) {
        guard immersive != isImmersive else { return }
        isImmersive = immersive
        onFullscreenChange?(immersive)
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
                self?.overlay.updateAdCountdown(remaining)
            }
            .store(in: &cancellables)
    }

    private func apply(_ state: VideoState) {
        currentState = state
        switch state {
        case .loading, .buffering:
            overlay.setBuffering(true)
        case .playing:
            overlay.clearError()
            overlay.setBuffering(false)
            overlay.setPlaying(true)
            liveReloadAttempts = 0
        case .paused:
            overlay.setBuffering(false)
            overlay.setPlaying(false)
        case .idle, .ended:
            overlay.setBuffering(false)
            overlay.setPlaying(false)
        case .error(let message):
            overlay.setBuffering(false)
            overlay.setPlaying(false)
            handlePlaybackError(message)
        }
    }

    private func handlePlaybackError(_ message: String) {
        guard !isResolving else { return }
        if case .live = source, liveReloadAttempts < 1 {
            liveReloadAttempts += 1
            logger.warn("Live playback error, re-resolving once: \(message)", category: .playback)
            resolveAndLoad()
            return
        }
        overlay.showError("Playback stopped.", symbol: "exclamationmark.triangle", canRetry: true)
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
            } catch {
                if Task.isCancelled || generation != self.resolveGeneration { return }
                self.isResolving = false
                self.logger.error("Video resolve failed: \(error.localizedDescription)", category: .playback)
                self.presentResolveFailure(error)
            }
        }
    }

    private func presentResolveFailure(_ error: Error) {
        overlay.setPlaying(false)
        let apiError = error as? APIError
        if apiError == .notFound || apiError == .forbidden {
            overlay.showError("This channel isn't live right now.", symbol: "tv.slash", canRetry: true)
        } else {
            overlay.showError("Couldn't load the stream.", symbol: "exclamationmark.triangle", canRetry: true)
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

    deinit {
        resolveTask?.cancel()
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
        liveReloadAttempts = 0
        resolveAndLoad()
    }

    func videoOverlayDidTapMute(_ overlay: VideoOverlayView) {
        isMuted.toggle()
        player.setMuted(isMuted)
        overlay.setMuted(isMuted)
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
}

extension VideoViewController: @MainActor AVPictureInPictureControllerDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        logger.error("PiP failed: \(error.localizedDescription)", category: .playback)
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        overlay.hideControls()
        setImmersive(false)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        setImmersive(isLandscape)
    }
}
