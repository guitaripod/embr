import Combine
import UIKit

@MainActor
final class VideoViewController: UIViewController {

    private let source: VideoSource
    private var player: VideoPlaying
    private let logger: AppLogger
    private let store: SettingsStore

    private let overlay = VideoOverlayView()
    private var cancellables = Set<AnyCancellable>()
    private var playerCancellables = Set<AnyCancellable>()

    private var currentState: VideoState = .idle
    private var streamActive: Bool
    private var hasLoaded = false

    init(
        source: VideoSource,
        player: VideoPlaying = WebViewPlayer(),
        logger: AppLogger = .shared,
        store: SettingsStore = .shared,
        active: Bool = true
    ) {
        self.source = source
        self.player = player
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
        bindPlayer()
        observeLifecycle()
        if streamActive { load() }
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
    }

    private func bindPlayer() {
        playerCancellables.removeAll()
        player.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.apply(state) }
            .store(in: &playerCancellables)
    }

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
            .sink { [weak self] in self?.handleForeground() }
            .store(in: &cancellables)
    }

    @objc private func handleBackground() {
        guard store.current.backgroundAudio == false else { return }
        player.pause()
    }

    @objc private func handleForeground() {
        guard streamActive else { return }
        switch currentState {
        case .idle, .ended, .error:
            load()
        default:
            player.play()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        OrientationCoordinator.mask = [.portrait, .landscapeLeft, .landscapeRight]
        UIApplication.shared.isIdleTimerDisabled = store.current.keepScreenAwake
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

    private var isLandscape: Bool { view.bounds.width > view.bounds.height }

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
            load()
        default:
            if hasLoaded { player.play() } else { load() }
        }
    }

    private func load() {
        hasLoaded = true
        overlay.clearError()
        overlay.setBuffering(true)
        player.load(source)
    }

    private func apply(_ state: VideoState) {
        currentState = state
        switch state {
        case .loading:
            overlay.setBuffering(true)
        case .playing:
            overlay.clearError()
            overlay.setBuffering(false)
        case .paused, .ended:
            overlay.setBuffering(false)
        case .idle:
            overlay.setBuffering(false)
        case .error(let message):
            overlay.setBuffering(false)
            let offline = message.localizedCaseInsensitiveContains("isn't live")
            overlay.showError(
                offline ? "This channel isn't live right now." : "Playback stopped.",
                symbol: offline ? "tv.slash" : "exclamationmark.triangle",
                canRetry: true
            )
        }
    }

    private func dismissSelf() {
        player.teardown()
        if let navigationController, navigationController.viewControllers.first !== self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension VideoViewController: VideoOverlayViewDelegate {
    func videoOverlayDidTapBack(_ overlay: VideoOverlayView) {
        dismissSelf()
    }

    func videoOverlayDidTapRetry(_ overlay: VideoOverlayView) {
        load()
    }
}
