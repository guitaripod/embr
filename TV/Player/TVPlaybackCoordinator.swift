import AVKit
import Combine
import UIKit
import EmbrCore
import MidgarCore

enum TVPlaybackRequest: Equatable, Sendable {
    case live(LiveStream)
    /// A channel by login whose stream is not known yet: a deep link, the Top Shelf, an avatar.
    case channel(login: String)
    case video(VideoOnDemand)
    case clip(Clip)
}

/// Plays one stream, past broadcast or clip in the system `AVPlayerViewController`, so the Apple TV's own controls do
/// the work: the transport bar, Siri, skipping and scrubbing on past broadcasts, the Info panel, match frame rate and
/// picture in picture with swapping. Embr adds, through the player's own extension points:
///
/// - chat beside the picture, in `contentOverlayView`, where the remote never focuses it;
/// - transport-bar items for chat, its placement and size, the quality, the star and multiview;
/// - a Channel tab in the info panel (swipe down);
/// - a channel switcher on the custom overlay (swipe up): who is live now, one click to switch;
/// - a Back to Live action when playback falls behind the live edge, and Start Over after a past broadcast resumes;
/// - the ad-break cover while Twitch plays ads the stream no longer carries.
///
/// The coordinator is the player's delegate and lives outside the view hierarchy, because picture in picture keeps
/// playing after the player view is gone.
@MainActor
final class TVPlaybackCoordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
    private static var active: TVPlaybackCoordinator?
    private static var pictureInPicture: TVPlaybackCoordinator?

    static func play(_ request: TVPlaybackRequest, from presenter: UIViewController) {
        if let active {
            active.start(request)
            return
        }
        let coordinator = TVPlaybackCoordinator()
        active = coordinator
        coordinator.present(from: presenter)
        coordinator.start(request)
    }

    /// Stops what is on screen, for the multiview, which plays several streams itself.
    static func endActive() {
        active?.finish()
    }

    private let playerVC = AVPlayerViewController()
    private let hls = HLSVideoPlayer()
    private let adView = TVAdBreakView()
    private let infoVC = TVStreamInfoViewController()
    private lazy var switcher = TVChannelSwitcherViewController { [weak self] stream in
        self?.start(.live(stream))
    }
    private var chatPanel: TVChatPanelView?
    private var chatConstraints: [NSLayoutConstraint] = []

    private var request: TVPlaybackRequest?
    private var stream: LiveStream?
    private var channel: ChannelInfo?
    private var metadata: [AVMetadataItem] = []
    private var resolveTask: Task<Void, Never>?
    private var tokenRefresh: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?
    private var edgeTimer: Timer?
    private var stateCancellables = Set<AnyCancellable>()
    private var isInPictureInPicture = false
    private var isFinished = false
    private var resumeOffered = false
    private var recoveries = 0

    private override init() {
        super.init()
        configurePlayer()
        bindPlayer()
    }

    private func configurePlayer() {
        playerVC.delegate = self
        playerVC.modalPresentationStyle = .fullScreen
        playerVC.modalTransitionStyle = .crossDissolve
        playerVC.allowsPictureInPicturePlayback = true
        playerVC.appliesPreferredDisplayCriteriaAutomatically = true
        playerVC.player = hls.avPlayer
        hls.setLayerAttached(false)
        hls.itemConfigurator = { [weak self] item in
            item.externalMetadata = self?.metadata ?? []
        }
        playerVC.customInfoViewControllers = [infoVC]

        guard let overlay = playerVC.contentOverlayView else { return }
        adView.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(adView)
        NSLayoutConstraint.activate([
            adView.topAnchor.constraint(equalTo: overlay.topAnchor),
            adView.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
            adView.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
            adView.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
        ])
    }

    private func present(from presenter: UIViewController) {
        Self.topmost(from: presenter).present(playerVC, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private static func topmost(from controller: UIViewController) -> UIViewController {
        var top = controller
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    private static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
    }

    private func start(_ request: TVPlaybackRequest) {
        self.request = request
        resolveTask?.cancel()
        tokenRefresh?.cancel()
        stallTask?.cancel()
        recoveries = 0
        resumeOffered = false
        playerVC.contextualActions = []
        adView.update(remaining: nil)
        stopChat()
        switch request {
        case .live(let stream):
            show(stream)
            #if DEBUG
            if DemoWorld.isActive {
                showDemoPicture(for: stream.userLogin)
                break
            }
            #endif
            resolveLive(login: stream.userLogin)
        case .channel(let login):
            resolveTask = Task { [weak self] in await self?.findStream(login: login) }
        case .video(let video):
            showVideo(video)
            resolveTask = Task { [weak self] in
                await self?.load(label: video.id) { try await AppContainer.shared.playback.resolveVOD(videoID: video.id) }
            }
        case .clip(let clip):
            stream = nil
            channel = nil
            playerVC.customOverlayViewController = nil
            setMetadata(TVPlayerMetadata.items(title: clip.title, subtitle: clip.broadcasterName, description: nil, artwork: nil))
            infoVC.show(title: clip.broadcasterName, subtitle: clip.title, detail: clip.creatorName, avatarURL: nil)
            resolveTask = Task { [weak self] in
                await self?.load(label: clip.id) {
                    PlaybackResolution(masterPlaylistURL: try await PlaybackResolver.shared.resolveClip(slug: clip.id))
                }
            }
        }
        refreshMenus()
    }

    private func show(_ stream: LiveStream) {
        self.stream = stream
        let channel = ChannelInfo(
            id: stream.userID, broadcasterLogin: stream.userLogin, broadcasterName: stream.userName,
            gameID: stream.gameID, gameName: stream.gameName, title: stream.title, language: stream.language,
            tags: stream.tags, isLive: true
        )
        self.channel = channel
        playerVC.customOverlayViewController = switcher
        setMetadata(TVPlayerMetadata.live(stream, artwork: nil))
        infoVC.show(stream, avatarURL: TVLiveDirectory.shared.avatar(for: stream.userID))
        WatchHistoryStore.shared.record(id: stream.userID, login: stream.userLogin, name: stream.userName)
        loadArtwork(for: stream)
        if SettingsStore.shared.current.tvChatVisibleEnabled {
            startChat(channel: channel, mode: .live)
        }
    }

    private func showVideo(_ video: VideoOnDemand) {
        stream = nil
        let channel = ChannelInfo(
            id: video.userID, broadcasterLogin: video.userLogin, broadcasterName: video.userName,
            gameID: "", gameName: "", title: video.title, language: ""
        )
        self.channel = channel
        playerVC.customOverlayViewController = nil
        let date = video.createdAt.formatted(date: .abbreviated, time: .omitted)
        setMetadata(TVPlayerMetadata.items(title: video.title, subtitle: "\(video.userName) · \(date)", description: nil, artwork: nil))
        infoVC.show(
            title: video.userName, subtitle: video.title,
            detail: String(localized: "Streamed \(date) · \(video.viewCount.formatted()) views"),
            avatarURL: TVLiveDirectory.shared.avatar(for: video.userID)
        )
        if SettingsStore.shared.current.tvChatVisibleEnabled {
            startChat(channel: channel, mode: .vod(videoID: video.id))
        }
    }

    private func findStream(login: String) async {
        let api = AppContainer.shared.api
        guard let user = try? await api.user(login: login) else {
            presentFailure(String(localized: "\(login) couldn't be found on Twitch."), retry: nil)
            return
        }
        guard !Task.isCancelled else { return }
        if let live = try? await api.streams(userIDs: [user.id]).first {
            start(.live(live))
        } else {
            presentOffline(name: user.displayName, login: user.login)
        }
    }

    private func resolveLive(login: String) {
        guard !RemoteConfigService.shared.startsLiveInEmbed else {
            presentFailure(String(localized: "Live playback is paused on Apple TV while Twitch changes how streams are delivered. Past broadcasts and clips still play."), retry: nil)
            return
        }
        resolveTask = Task { [weak self] in
            await self?.load(label: login) { try await AppContainer.shared.playback.resolveLive(channelLogin: login) }
        }
    }

    private func load(label: String, _ resolve: @escaping @Sendable () async throws -> PlaybackResolution) async {
        do {
            let resolution = try await resolve()
            guard !Task.isCancelled, !isFinished else { return }
            hls.load(resolution)
            scheduleTokenRefresh(resolution.expiresAt, resolve: resolve)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            let apiError = error as? APIError
            if (apiError == .notFound || apiError == .forbidden), let stream {
                presentOffline(name: stream.userName, login: stream.userLogin)
            } else {
                MidgarLog.notice("tv: resolve failed for \(label): \(error)", category: .playback)
                presentFailure(error.localizedDescription) { [weak self] in
                    guard let self, let request = self.request else { return }
                    self.start(request)
                }
            }
        }
    }

    /// Twitch's playback token lapses after a while; the stream is resolved again two minutes before it does.
    private func scheduleTokenRefresh(_ expiresAt: Date?, resolve: @escaping @Sendable () async throws -> PlaybackResolution) {
        tokenRefresh?.cancel()
        guard case .live = request else { return }
        let delay = expiresAt.map { max(60, $0.timeIntervalSinceNow - 120) } ?? 50 * 60
        tokenRefresh = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, !self.isFinished else { return }
            MidgarLog.info("tv: playback token nearing expiry, re-resolving", category: .playback)
            guard let resolution = try? await resolve() else { return }
            self.hls.load(resolution)
            self.scheduleTokenRefresh(resolution.expiresAt, resolve: resolve)
        }
    }

    private func bindPlayer() {
        hls.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handle(state) }
            .store(in: &stateCancellables)
        hls.adBreakPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] remaining in self?.adView.update(remaining: remaining) }
            .store(in: &stateCancellables)
        hls.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in self?.handle(progress) }
            .store(in: &stateCancellables)
    }

    private func handle(_ state: VideoState) {
        switch state {
        case .playing:
            stallTask?.cancel()
            recoveries = 0
            refreshMenus()
            startEdgeWatch()
        case .buffering, .loading:
            watchForStall()
        case .error(let message):
            presentFailure(message) { [weak self] in
                guard let self, let request = self.request else { return }
                self.start(request)
            }
        case .ended:
            if case .live = request, let stream {
                presentOffline(name: stream.userName, login: stream.userLogin)
            }
        case .idle, .paused:
            break
        }
    }

    /// A live stream stuck buffering for fifteen seconds is resolved again, up to three times in a row.
    private func watchForStall() {
        guard case .live = request, stallTask == nil || stallTask?.isCancelled == true else { return }
        stallTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.recoveries < 3, case .live(let stream) = self.request else { return }
            self.recoveries += 1
            MidgarLog.notice("tv: stall watchdog fired, recovery \(self.recoveries)", category: .playback)
            self.resolveLive(login: stream.userLogin)
            self.stallTask = nil
        }
    }

    private func handle(_ progress: PlaybackProgress) {
        guard case .video(let video) = request, progress.current > 0 else { return }
        offerResume(for: video, duration: progress.duration)
        chatPanel?.setPlayback(seconds: progress.current)
        guard progress.current > 5 else { return }
        TVResumePositions.save(progress.current, duration: progress.duration, for: video.id)
    }

    /// Picks a past broadcast up where the viewer left it, and offers Start Over for a few seconds.
    private func offerResume(for video: VideoOnDemand, duration: TimeInterval) {
        guard !resumeOffered, duration > 0 else { return }
        resumeOffered = true
        guard let position = TVResumePositions.position(for: video.id, duration: duration) else { return }
        hls.seek(to: position)
        playerVC.contextualActions = [
            UIAction(title: String(localized: "Start Over"), image: UIImage(systemName: "backward.end.fill")) { [weak self] _ in
                self?.hls.seek(to: 0)
                self?.playerVC.contextualActions = []
            },
        ]
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            self?.playerVC.contextualActions = []
        }
    }

    /// Offers Back to Live while a live stream plays more than twenty seconds behind its edge, after a pause or a skip
    /// back.
    private func startEdgeWatch() {
        edgeTimer?.invalidate()
        guard case .live = request else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateEdgeAction() }
        }
        RunLoop.main.add(timer, forMode: .common)
        edgeTimer = timer
    }

    private func updateEdgeAction() {
        guard let item = hls.avPlayer.currentItem, let range = item.seekableTimeRanges.last?.timeRangeValue else { return }
        let behind = range.end.seconds - item.currentTime().seconds
        let showing = !playerVC.contextualActions.isEmpty
        if behind > 20, !showing {
            playerVC.contextualActions = [
                UIAction(title: String(localized: "Back to Live"), image: UIImage(systemName: "dot.radiowaves.left.and.right")) { [weak self] _ in
                    self?.hls.seekToLive()
                    self?.hls.play()
                    self?.playerVC.contextualActions = []
                },
            ]
        } else if behind < 10, showing {
            playerVC.contextualActions = []
        }
    }

    #if DEBUG
    /// The invented channels of a screenshot capture have no stream; their picture stands in under the chat.
    private func showDemoPicture(for login: String) {
        guard let overlay = chatHost else { return }
        let picture = UIImageView(image: DemoArt.stream(key: login, size: CGSize(width: 1920, height: 1080), facecam: true))
        picture.contentMode = .scaleAspectFill
        picture.frame = overlay.bounds
        picture.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.addSubview(picture)
    }
    #endif

    private func setMetadata(_ items: [AVMetadataItem]) {
        metadata = items
        hls.avPlayer.currentItem?.externalMetadata = items
    }

    private func loadArtwork(for stream: LiveStream) {
        Task { [weak self] in
            await TVLiveDirectory.shared.loadAvatars(for: [stream.userID])
            guard let url = TVLiveDirectory.shared.avatar(for: stream.userID),
                  let image = await AppContainer.shared.images.image(for: url, targetScale: 1),
                  let self, self.stream?.userID == stream.userID else { return }
            self.setMetadata(TVPlayerMetadata.live(stream, artwork: image))
            self.infoVC.show(stream, avatarURL: url)
        }
    }

    private func startChat(channel: ChannelInfo, mode: ChatRoom.Mode) {
        Task { [weak self] in
            let user = await AppContainer.shared.auth.currentUser()
            guard let self, !self.isFinished, self.channel == channel else { return }
            let room = AppContainer.shared.makeChatRoom(channel: channel, loggedIn: user != nil, mode: mode)
            let viewModel = ChatViewModel(room: room, currentUserLogin: user?.login)
            let title = mode == .live
                ? channel.broadcasterName
                : String(localized: "Chat Replay · \(channel.broadcasterName)")
            let panel = TVChatPanelView(viewModel: viewModel, title: title)
            self.install(panel)
            panel.start()
        }
    }

    /// Where chat goes: between the picture and the controls, or, for an invented stream with no picture to play,
    /// above the player's own loading indicator.
    private var chatHost: UIView? {
        #if DEBUG
        if DemoWorld.isActive { return playerVC.view }
        #endif
        return playerVC.contentOverlayView
    }

    private func install(_ panel: TVChatPanelView) {
        guard let overlay = chatHost else { return }
        chatPanel?.stop()
        chatPanel?.removeFromSuperview()
        chatPanel = panel
        panel.translatesAutoresizingMaskIntoConstraints = false
        if adView.superview === overlay {
            overlay.insertSubview(panel, belowSubview: adView)
        } else {
            overlay.addSubview(panel)
        }
        placeChat()
        panel.alpha = 0
        UIView.animate(withDuration: TVMetrics.Duration.panel) { panel.alpha = 1 }
    }

    private func placeChat() {
        guard let panel = chatPanel, let overlay = chatHost else { return }
        NSLayoutConstraint.deactivate(chatConstraints)
        let edge = SettingsStore.shared.current.tvChatPlacementPreference == .left
            ? panel.leadingAnchor.constraint(equalTo: overlay.leadingAnchor)
            : panel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor)
        chatConstraints = [
            edge,
            panel.topAnchor.constraint(equalTo: overlay.topAnchor),
            panel.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
            panel.widthAnchor.constraint(equalToConstant: TVChatPanelView.width),
        ]
        NSLayoutConstraint.activate(chatConstraints)
    }

    private func stopChat() {
        guard let panel = chatPanel else { return }
        chatPanel = nil
        panel.stop()
        UIView.animate(withDuration: TVMetrics.Duration.panel, animations: { panel.alpha = 0 }, completion: { _ in panel.removeFromSuperview() })
    }

    private func setChatVisible(_ visible: Bool) {
        SettingsStore.shared.update { $0.tvChatVisible = visible }
        if visible, let channel {
            if case .video(let video) = request {
                startChat(channel: channel, mode: .vod(videoID: video.id))
            } else if stream != nil {
                startChat(channel: channel, mode: .live)
            }
        } else {
            stopChat()
        }
        refreshMenus()
    }

    private func refreshMenus() {
        var items: [UIMenuElement] = []
        let chatAvailable = channel != nil
        let chatVisible = chatPanel != nil || (chatAvailable && SettingsStore.shared.current.tvChatVisibleEnabled)
        if chatAvailable {
            let chat = UIAction(
                title: String(localized: "Chat"),
                image: UIImage(systemName: chatVisible ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
            ) { [weak self] _ in
                self?.setChatVisible(!chatVisible)
            }
            chat.state = chatVisible ? .on : .off
            items.append(chat)
        }
        if chatAvailable && chatVisible {
            items.append(chatOptionsMenu())
        }
        if let quality = qualityMenu() {
            items.append(quality)
        }
        if let stream {
            items.append(favoriteAction(for: stream))
            items.append(UIAction(title: String(localized: "Multiview"), image: UIImage(systemName: "rectangle.split.2x2")) { [weak self] _ in
                self?.openMultiview(with: stream)
            })
        }
        playerVC.transportBarCustomMenuItems = items
    }

    private func chatOptionsMenu() -> UIMenu {
        let settings = SettingsStore.shared.current
        let placement = UIMenu(title: String(localized: "Placement"), options: .displayInline, children: Settings.ChatPlacement.allCases.map { side in
            let action = UIAction(title: side == .left ? String(localized: "Left") : String(localized: "Right")) { [weak self] _ in
                SettingsStore.shared.update { $0.tvChatPlacement = side }
                self?.placeChat()
                self?.refreshMenus()
            }
            action.state = settings.tvChatPlacementPreference == side ? .on : .off
            return action
        })
        let size = UIMenu(title: String(localized: "Text Size"), options: .displayInline, children: Settings.ChatTextSize.allCases.map { textSize in
            let title: String = switch textSize {
            case .small: String(localized: "Small")
            case .medium: String(localized: "Medium")
            case .large: String(localized: "Large")
            }
            let action = UIAction(title: title) { [weak self] _ in
                SettingsStore.shared.update { $0.tvChatTextSize = textSize }
                self?.chatPanel?.relayout()
                self?.refreshMenus()
            }
            action.state = settings.tvChatTextSizePreference == textSize ? .on : .off
            return action
        })
        return UIMenu(title: String(localized: "Chat Options"), image: UIImage(systemName: "textformat.size"), children: [placement, size])
    }

    private func qualityMenu() -> UIMenu? {
        let qualities = hls.availableQualities.filter { !$0.isAudioOnly }
        guard !qualities.isEmpty else { return nil }
        let current = hls.currentQuality
        var actions = [UIAction(title: String(localized: "Auto")) { [weak self] _ in
            guard let self, let auto = StreamQuality.auto(from: qualities) else { return }
            self.hls.setQuality(auto)
            self.refreshMenus()
        }]
        actions[0].state = current == nil ? .on : .off
        for quality in qualities {
            let action = UIAction(title: quality.displayName) { [weak self] _ in
                self?.hls.setQuality(quality)
                self?.refreshMenus()
            }
            action.state = current == quality ? .on : .off
            actions.append(action)
        }
        return UIMenu(title: String(localized: "Quality"), image: UIImage(systemName: "slider.horizontal.3"), options: .singleSelection, children: actions)
    }

    private func favoriteAction(for stream: LiveStream) -> UIAction {
        let favorite = FavoritesStore.shared.isFavorite(stream.userID)
        let action = UIAction(
            title: favorite ? String(localized: "Favorited") : String(localized: "Favorite"),
            image: UIImage(systemName: favorite ? "star.fill" : "star")
        ) { [weak self] _ in
            FavoritesStore.shared.toggle(id: stream.userID, login: stream.userLogin, name: stream.userName)
            self?.refreshMenus()
        }
        action.state = favorite ? .on : .off
        return action
    }

    private func openMultiview(with stream: LiveStream) {
        let root = Self.rootViewController
        finish()
        guard let root else { return }
        TVMultiviewViewController.present(starting: [stream], from: root)
    }

    private func presentOffline(name: String, login: String) {
        let message = String(localized: "\(name.isEmpty ? login : name) isn't live right now.")
        let alert = UIAlertController(title: String(localized: "Offline"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Open Channel"), style: .default) { [weak self] _ in
            self?.closeThen { root in TVRouter.openChannel(login: login, from: root) }
        })
        alert.addAction(UIAlertAction(title: String(localized: "Close"), style: .cancel) { [weak self] _ in
            self?.closeThen { _ in }
        })
        Self.topmost(from: playerVC).present(alert, animated: true)
    }

    private func presentFailure(_ message: String, retry: (() -> Void)?) {
        guard Self.topmost(from: playerVC) as? UIAlertController == nil else { return }
        let alert = UIAlertController(title: String(localized: "Can't Play"), message: message, preferredStyle: .alert)
        if let retry {
            alert.addAction(UIAlertAction(title: String(localized: "Try Again"), style: .default) { _ in retry() })
        }
        alert.addAction(UIAlertAction(title: String(localized: "Close"), style: .cancel) { [weak self] _ in
            self?.closeThen { _ in }
        })
        Self.topmost(from: playerVC).present(alert, animated: true)
    }

    private func closeThen(_ next: @escaping (UIViewController) -> Void) {
        let root = Self.rootViewController
        playerVC.dismiss(animated: true) { [weak self] in
            self?.finish()
            if let root { next(root) }
        }
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        resolveTask?.cancel()
        tokenRefresh?.cancel()
        stallTask?.cancel()
        edgeTimer?.invalidate()
        edgeTimer = nil
        stopChat()
        hls.teardown()
        playerVC.player = nil
        if playerVC.presentingViewController != nil {
            playerVC.dismiss(animated: false)
        }
        if Self.active === self { Self.active = nil }
        if Self.pictureInPicture === self { Self.pictureInPicture = nil }
        MidgarLog.info("tv: playback finished", category: .playback)
    }

    func playerViewControllerDidEndDismissalTransition(_ playerViewController: AVPlayerViewController) {
        guard !isInPictureInPicture else { return }
        finish()
    }

    /// Chat steps back while the transport bar is up, so the controls never sit on top of moving text.
    func playerViewController(
        _ playerViewController: AVPlayerViewController,
        willTransitionToVisibilityOfTransportBar visible: Bool,
        with coordinator: any AVPlayerViewControllerAnimationCoordinator
    ) {
        let panel = chatPanel
        coordinator.addCoordinatedAnimations({
            panel?.alpha = visible ? 0.18 : 1
        }, completion: nil)
    }

    func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_ playerViewController: AVPlayerViewController) -> Bool {
        true
    }

    func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        isInPictureInPicture = true
        if let other = Self.pictureInPicture, other !== self {
            other.finish()
        }
        Self.pictureInPicture = self
        if Self.active === self { Self.active = nil }
    }

    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        isInPictureInPicture = false
        if Self.pictureInPicture === self { Self.pictureInPicture = nil }
        if playerVC.presentingViewController == nil, Self.active !== self {
            finish()
        }
    }

    func playerViewController(
        _ playerViewController: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        guard let root = Self.rootViewController else {
            completionHandler(false)
            return
        }
        if let other = Self.active, other !== self, other.playerVC.presentingViewController != nil {
            other.playerVC.dismiss(animated: false)
        }
        Self.active = self
        Self.topmost(from: root).present(playerVC, animated: false) {
            completionHandler(true)
        }
    }
}

extension StreamQuality {
    /// The name the quality menu shows: Twitch's `chunked` is the source rendition.
    var displayName: String {
        name.lowercased() == "chunked" ? String(localized: "Source") : name
    }

    /// A stand-in quality the player reads as "Auto": no peak bit rate, the master playlist chooses.
    static func auto(from qualities: [StreamQuality]) -> StreamQuality? {
        guard let first = qualities.first else { return nil }
        return StreamQuality(name: "Auto", url: first.url)
    }
}
