import UIKit
import AuthenticationServices
import Combine
import EmbrCore
import SafariServices

@MainActor
final class ChannelViewController: UIViewController {
    private let channel: ChannelInfo
    private let auth: AuthService
    private let store: SettingsStore

    private var chatController: ChatViewController?
    private var videoController: VideoViewController?
    private var chatLoggedIn: Bool?
    private var isChatOnly = false
    private var isAudioOnly = false
    private let audioBar = AudioOnlyBarView()
    private var cancellables = Set<AnyCancellable>()

    private lazy var chatOnlyItem = UIBarButtonItem(
        image: UIImage(systemName: "bubble.left.and.bubble.right"),
        style: .plain,
        target: self,
        action: #selector(toggleChatOnly)
    )

    private lazy var videosItem = UIBarButtonItem(
        image: UIImage(systemName: "film.stack"),
        style: .plain,
        target: self,
        action: #selector(showVideos)
    )

    private lazy var favoriteItem = UIBarButtonItem(
        image: UIImage(systemName: "star"),
        style: .plain,
        target: self,
        action: #selector(toggleFavorite)
    )

    @objc private func toggleFavorite() {
        let added = FavoritesStore.shared.toggle(
            id: channel.id, login: channel.broadcasterLogin, name: channel.broadcasterName)
        Haptics.notify(added ? .success : .warning)
    }

    private func updateFavoriteButton() {
        let isFavorite = FavoritesStore.shared.isFavorite(channel.id)
        favoriteItem.image = UIImage(systemName: isFavorite ? "star.fill" : "star")
        favoriteItem.accessibilityLabel = isFavorite
            ? String(localized: "Remove from Favorites")
            : String(localized: "Add to Favorites")
    }

    private func observeFavorites() {
        FavoritesStore.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateFavoriteButton() }
            }
            .store(in: &cancellables)
    }

    @objc private func showVideos() {
        navigationController?.pushViewController(
            ChannelVideosViewController(broadcasterID: channel.id, channelName: channel.broadcasterName),
            animated: true
        )
    }

    private let containerStack = UIStackView()
    private let videoContainer = UIView()
    private let chatContainer = UIView()
    private let dividerHandle = UIView()
    private let infoView = StreamInfoView()
    private var gameToOpen: GameCategory?

    private var chatWidthFraction: CGFloat = 0.32
    private var landscapeWidthConstraint: NSLayoutConstraint?
    private lazy var dividerPan = UIPanGestureRecognizer(target: self, action: #selector(handleDividerPan(_:)))
    private var isVideoFullscreen = false
    private let chatOverlay = UIView()
    private lazy var chatOverlayDoubleTap: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleOverlayDoubleTap))
        recognizer.numberOfTapsRequired = 2
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()

    private let eventCard = ChannelEventCardView()
    private lazy var eventsPoller = ChannelEventsPoller(login: channel.broadcasterLogin)
    private lazy var liveStatsPoller = LiveStatsPoller(userID: channel.id)
    private var dismissedEventID: String?
    private var currentEventID: String?

    init(channel: ChannelInfo, auth: AuthService = AuthService.shared, store: SettingsStore = .shared) {
        self.channel = channel
        self.auth = auth
        self.store = store
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var watchStartedAt: Date?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        [.portrait, .landscapeLeft, .landscapeRight]
    }

    override var prefersStatusBarHidden: Bool { isLandscape }
    override var prefersHomeIndicatorAutoHidden: Bool { isLandscape }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        watchStartedAt = Date()
        navigationController?.setNavigationBarHidden(isLandscape, animated: animated)
        eventsPoller.start()
        liveStatsPoller.start()
        eventCard.resume()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let startedAt = watchStartedAt {
            ReviewPrompt.recordWatchTime(
                Date().timeIntervalSince(startedAt), in: view.window?.windowScene)
            watchStartedAt = nil
        }
        navigationController?.setNavigationBarHidden(false, animated: animated)
        eventsPoller.stop()
        liveStatsPoller.stop()
        eventCard.pause()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = channel.broadcasterName
        navigationItem.largeTitleDisplayMode = .never
        isChatOnly = store.current.chatOnly ?? false
        navigationItem.rightBarButtonItems = [chatOnlyItem, videosItem, favoriteItem]
        updateChatOnlyButton()
        updateFavoriteButton()
        observeFavorites()
        setUpLayout()
        loadChildren()
        loadStreamInfo()
        observeAuth()
        setUpEventCard()
        WatchHistoryStore.shared.record(id: channel.id, login: channel.broadcasterLogin, name: channel.broadcasterName)
        #if DEBUG
        applyScreenshotPose()
        #endif
    }

    #if DEBUG
    private func applyScreenshotPose() {
        let pose = ScreenshotHarness.channelPose
        guard pose != .normal else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            switch pose {
            case .audio: self.videoController?.setAudioOnly(true)
            case .chat: self.setChatOnly(true)
            case .normal: break
            }
        }
    }
    #endif

    private func setUpEventCard() {
        eventCard.translatesAutoresizingMaskIntoConstraints = false
        eventCard.isHidden = true
        eventCard.onDismiss = { [weak self] in
            guard let self else { return }
            self.dismissedEventID = self.currentEventID
            self.eventCard.update(.empty)
        }
        chatContainer.addSubview(eventCard)
        NSLayoutConstraint.activate([
            eventCard.topAnchor.constraint(equalTo: chatContainer.safeAreaLayoutGuide.topAnchor, constant: 8),
            eventCard.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor, constant: 8),
            eventCard.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor, constant: -8)
        ])
        eventsPoller.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let id = events.prediction?.id ?? events.poll?.id
                    self.currentEventID = id
                    if let id, id == self.dismissedEventID {
                        self.eventCard.update(.empty)
                        return
                    }
                    self.eventCard.update(events)
                    self.chatContainer.bringSubviewToFront(self.eventCard)
                }
            }
            .store(in: &cancellables)
    }

    private var avatarURL: URL?

    private func loadStreamInfo() {
        infoView.configure(channel: channel)
        audioBar.configure(name: channel.broadcasterName, title: channel.title)
        videoController?.setNowPlayingMetadata(title: channel.title, channelName: channel.broadcasterName)
        gameToOpen = channel.gameName.isEmpty ? nil : GameCategory(id: channel.gameID, name: channel.gameName, boxArtURLTemplate: "")
        infoView.onTapGame = { [weak self] in
            guard let self, let game = self.gameToOpen else { return }
            self.navigationController?.pushViewController(TopViewController(mode: .game(game), api: AppContainer.shared.api), animated: true)
        }
        observeLiveStats()
        Task { [weak self] in
            guard let self else { return }
            let avatarURL = try? await AppContainer.shared.api.users(ids: [self.channel.id]).first?.profileImageURL
            self.avatarURL = avatarURL ?? nil
            if let stream = try? await AppContainer.shared.api.streams(userIDs: [self.channel.id]).first {
                self.applyLiveStream(stream)
            } else {
                self.applyMetadata(title: self.channel.title)
            }
            if let avatarURL = self.avatarURL,
               let image = await ImageLoader.shared.image(for: avatarURL, targetScale: 2.0) {
                self.audioBar.setAvatar(image)
            }
        }
    }

    private func observeLiveStats() {
        liveStatsPoller.status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch status {
                    case .live(let stream): self.applyLiveStream(stream)
                    case .offline: self.applyOffline()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private var isStreamOffline = false
    private var lastAppliedTitle: String?

    private func applyLiveStream(_ stream: LiveStream) {
        isStreamOffline = false
        infoView.configure(stream: stream)
        if !stream.gameName.isEmpty {
            gameToOpen = GameCategory(id: stream.gameID, name: stream.gameName, boxArtURLTemplate: "")
        }
        guard lastAppliedTitle != stream.title else { return }
        lastAppliedTitle = stream.title
        applyMetadata(title: stream.title)
    }

    private func applyOffline() {
        guard !isStreamOffline else { return }
        isStreamOffline = true
        gameToOpen = nil
        lastAppliedTitle = nil
        infoView.setOffline()
        applyMetadata(title: channel.title)
    }

    private func applyMetadata(title: String) {
        audioBar.configure(name: channel.broadcasterName, title: title)
        videoController?.setNowPlayingMetadata(
            title: title,
            channelName: channel.broadcasterName,
            avatarURL: avatarURL
        )
    }

    @objc private func toggleChatOnly() {
        setChatOnly(!isChatOnly)
    }

    private func updateChatOnlyButton() {
        chatOnlyItem.image = UIImage(systemName: isChatOnly ? "tv" : "bubble.left.and.bubble.right")
        chatOnlyItem.accessibilityLabel = isChatOnly ? String(localized: "Show Video") : String(localized: "Chat Only")
    }

    private func setChatOnly(_ on: Bool) {
        guard on != isChatOnly else { return }
        if isVideoFullscreen { setVideoFullscreen(false) }
        Haptics.selection(store)
        isChatOnly = on
        store.update { $0.chatOnly = on }
        updateChatOnlyButton()
        if isAudioOnly {
            if on {
                videoController?.exitAudioOnlyKeepingPlayerVariant()
            } else {
                videoController?.setAudioOnly(false)
            }
        }
        videoController?.setStreamActive(!on)
        if on {
            videoContainer.removeConstraints(videoAspectConstraints)
            videoAspectConstraints = []
        }
        videoContainer.isHidden = on
        applyOrientation(isLandscape: isLandscape)
    }

    private func observeAuth() {
        auth.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                MainActor.assumeIsolated { self?.handleAuthChange(state) }
            }
            .store(in: &cancellables)
    }

    private func handleAuthChange(_ state: AuthState) {
        let user: AuthenticatedUser?
        switch state {
        case .anonymous: user = nil
        case .authenticated(let authed): user = authed
        }
        guard let current = chatLoggedIn, current != (user != nil) else { return }
        reattachChat(user: user)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        let landscape = size.width > size.height
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.applyOrientation(isLandscape: landscape)
            self?.setVideoFullscreen(landscape)
        })
    }

    private var isLandscape: Bool { view.bounds.width > view.bounds.height }

    private func setUpLayout() {
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        containerStack.alignment = .fill
        containerStack.distribution = .fill
        view.addSubview(containerStack)

        videoContainer.translatesAutoresizingMaskIntoConstraints = false
        videoContainer.backgroundColor = .black
        chatContainer.translatesAutoresizingMaskIntoConstraints = false
        chatContainer.backgroundColor = Theme.background

        containerStack.addArrangedSubview(videoContainer)
        containerStack.addArrangedSubview(infoView)
        containerStack.addArrangedSubview(chatContainer)

        dividerHandle.translatesAutoresizingMaskIntoConstraints = false
        dividerHandle.backgroundColor = Theme.surfaceElevated
        dividerHandle.addGestureRecognizer(dividerPan)

        videoContainer.isHidden = isChatOnly
        chatOverlay.addGestureRecognizer(chatOverlayDoubleTap)

        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            containerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerStack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        applyOrientation(isLandscape: isLandscape)
    }

    private func applyOrientation(isLandscape landscape: Bool) {
        navigationController?.setNavigationBarHidden(landscape && !isAudioOnly, animated: true)
        videoController?.setBackButtonHidden(navigationController != nil && !landscape)
        infoView.isHidden = landscape || isChatOnly || isAudioOnly
        if landscape, !isAudioOnly {
            containerStack.axis = .horizontal
            landscapeWidthConstraint?.isActive = false
            if isChatOnly {
                removeDivider()
                landscapeWidthConstraint = nil
            } else {
                installDivider()
                let constraint = chatContainer.widthAnchor.constraint(equalTo: containerStack.widthAnchor, multiplier: chatWidthFraction)
                constraint.isActive = true
                landscapeWidthConstraint = constraint
            }
            videoContainer.removeConstraints(videoAspectConstraints)
            videoAspectConstraints = []
        } else {
            containerStack.axis = .vertical
            removeDivider()
            landscapeWidthConstraint?.isActive = false
            landscapeWidthConstraint = nil
            if !isChatOnly, !isAudioOnly { applyPortraitVideoAspect() }
        }
        view.layoutIfNeeded()
    }

    /// Collapses the video area to a compact audio bar (chat fills the screen) or
    /// restores the full video layout. Session-only: the layout is forced vertical
    /// while audio-only so chat stays primary in both orientations.
    private func applyAudioOnly(_ on: Bool) {
        guard on != isAudioOnly else { return }
        if on, isVideoFullscreen { setVideoFullscreen(false) }
        isAudioOnly = on
        Haptics.selection(store)
        if on {
            videoContainer.removeConstraints(videoAspectConstraints)
            videoAspectConstraints = []
            videoContainer.isHidden = true
            if audioBar.superview == nil {
                containerStack.insertArrangedSubview(audioBar, at: 0)
            }
            audioBar.isHidden = false
        } else {
            audioBar.isHidden = true
            audioBar.removeFromSuperview()
            videoContainer.isHidden = isChatOnly
        }
        applyOrientation(isLandscape: isLandscape)
    }

    private var videoAspectConstraints: [NSLayoutConstraint] = []

    private func applyPortraitVideoAspect() {
        videoContainer.removeConstraints(videoAspectConstraints)
        let aspect = videoContainer.heightAnchor.constraint(equalTo: videoContainer.widthAnchor, multiplier: 9.0 / 16.0)
        aspect.priority = .required
        aspect.isActive = true
        videoAspectConstraints = [aspect]
    }

    private func installDivider() {
        guard dividerHandle.superview == nil else { return }
        view.addSubview(dividerHandle)
        NSLayoutConstraint.activate([
            dividerHandle.topAnchor.constraint(equalTo: containerStack.topAnchor),
            dividerHandle.bottomAnchor.constraint(equalTo: containerStack.bottomAnchor),
            dividerHandle.trailingAnchor.constraint(equalTo: chatContainer.leadingAnchor),
            dividerHandle.widthAnchor.constraint(equalToConstant: 8)
        ])
    }

    private func removeDivider() {
        dividerHandle.removeFromSuperview()
    }

    @objc private func handleDividerPan(_ recognizer: UIPanGestureRecognizer) {
        guard isLandscape else { return }
        let translation = recognizer.translation(in: containerStack)
        let totalWidth = containerStack.bounds.width
        guard totalWidth > 0 else { return }
        let delta = -translation.x / totalWidth
        let proposed = min(0.6, max(0.2, chatWidthFraction + delta))
        landscapeWidthConstraint?.isActive = false
        let constraint = chatContainer.widthAnchor.constraint(equalTo: containerStack.widthAnchor, multiplier: proposed)
        constraint.isActive = true
        landscapeWidthConstraint = constraint
        view.layoutIfNeeded()
        if recognizer.state == .ended || recognizer.state == .cancelled {
            chatWidthFraction = proposed
            recognizer.setTranslation(.zero, in: containerStack)
        }
    }

    func setVideoFullscreen(_ fullscreen: Bool) {
        let immersive = fullscreen && !isChatOnly && !isAudioOnly
        videoController?.setImmersiveState(immersive)
        guard immersive != isVideoFullscreen, let chat = chatController else { return }
        isVideoFullscreen = immersive
        if immersive {
            installChatOverlay(chat: chat)
        } else {
            removeChatOverlay(chat: chat)
        }
        view.layoutIfNeeded()
    }

    private var fullscreenChatHidden = false

    @objc private func handleOverlayDoubleTap() {
        toggleFullscreenChat()
    }

    private func toggleFullscreenChat() {
        guard isVideoFullscreen else { return }
        fullscreenChatHidden.toggle()
        chatOverlay.isUserInteractionEnabled = !fullscreenChatHidden
        Haptics.impact(.light)
        UIView.animate(withDuration: 0.25) {
            self.chatOverlay.alpha = self.fullscreenChatHidden ? 0 : 1
        }
    }

    private func installChatOverlay(chat: ChatViewController) {
        chatContainer.isHidden = true
        fullscreenChatHidden = false
        chatOverlay.alpha = 1
        chatOverlay.isUserInteractionEnabled = true
        chatOverlay.translatesAutoresizingMaskIntoConstraints = false
        chatOverlay.backgroundColor = Theme.background.withAlphaComponent(0.35)
        videoContainer.addSubview(chatOverlay)
        chat.view.removeFromSuperview()
        chatOverlay.addSubview(chat.view)
        NSLayoutConstraint.activate([
            chatOverlay.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            chatOverlay.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),
            chatOverlay.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            chatOverlay.widthAnchor.constraint(equalTo: videoContainer.widthAnchor, multiplier: 0.34),
            chat.view.topAnchor.constraint(equalTo: chatOverlay.topAnchor),
            chat.view.leadingAnchor.constraint(equalTo: chatOverlay.leadingAnchor),
            chat.view.trailingAnchor.constraint(equalTo: chatOverlay.trailingAnchor),
            chat.view.bottomAnchor.constraint(equalTo: chatOverlay.bottomAnchor)
        ])
    }

    private func removeChatOverlay(chat: ChatViewController) {
        chat.view.removeFromSuperview()
        chatOverlay.removeFromSuperview()
        chatContainer.isHidden = false
        chatContainer.addSubview(chat.view)
        NSLayoutConstraint.activate([
            chat.view.topAnchor.constraint(equalTo: chatContainer.topAnchor),
            chat.view.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor),
            chat.view.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor),
            chat.view.bottomAnchor.constraint(equalTo: chatContainer.bottomAnchor)
        ])
    }

    private func loadChildren() {
        let video = VideoViewController(source: .live(login: channel.broadcasterLogin), active: !isChatOnly)
        video.onDoubleTapToggleChat = { [weak self] in
            self?.toggleFullscreenChat()
        }
        video.onAudioOnlyChanged = { [weak self] on in
            self?.applyAudioOnly(on)
        }
        video.onPlaybackStateChanged = { [weak self] playing in
            self?.audioBar.setPlaying(playing)
        }
        audioBar.onPlayPause = { [weak self] in
            self?.videoController?.togglePlayPause()
        }
        audioBar.onRestoreVideo = { [weak self] in
            self?.videoController?.setAudioOnly(false)
        }
        addChild(video)
        video.view.translatesAutoresizingMaskIntoConstraints = false
        videoContainer.addSubview(video.view)
        NSLayoutConstraint.activate([
            video.view.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            video.view.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            video.view.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            video.view.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor)
        ])
        video.didMove(toParent: self)
        videoController = video
        video.setBackButtonHidden(navigationController != nil && !isLandscape)

        Task { [weak self] in
            guard let self else { return }
            let user = await self.auth.currentUser()
            self.attachChat(user: user)
        }
    }

    private func attachChat(user: AuthenticatedUser?) {
        let loggedIn = user != nil
        let room = AppContainer.shared.makeChatRoom(channel: channel, loggedIn: loggedIn)
        let viewModel = ChatViewModel(room: room, currentUserLogin: user?.login)
        let chat = ChatViewController(viewModel: viewModel, isAnonymous: !loggedIn, currentUserLogin: user?.login, broadcasterLogin: channel.broadcasterLogin)
        chat.delegate = self
        addChild(chat)
        chat.view.translatesAutoresizingMaskIntoConstraints = false
        chatContainer.addSubview(chat.view)
        NSLayoutConstraint.activate([
            chat.view.topAnchor.constraint(equalTo: chatContainer.topAnchor),
            chat.view.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor),
            chat.view.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor),
            chat.view.bottomAnchor.constraint(equalTo: chatContainer.bottomAnchor)
        ])
        chat.didMove(toParent: self)
        chatController = chat
        chatLoggedIn = loggedIn
        setVideoFullscreen(isLandscape)
    }

    private func reattachChat(user: AuthenticatedUser?) {
        if isVideoFullscreen {
            isVideoFullscreen = false
            chatOverlay.removeFromSuperview()
            chatContainer.isHidden = false
        }
        if let existing = chatController {
            existing.endSession()
            existing.willMove(toParent: nil)
            existing.view.removeFromSuperview()
            existing.removeFromParent()
            chatController = nil
        }
        attachChat(user: user)
    }
}

extension ChannelViewController: ChatViewControllerDelegate {
    func chatViewController(_ controller: ChatViewController, didTapUsername user: ChatUser) {
        Haptics.selection()
        present(ProfileSheetViewController(login: user.login, navigator: navigationController), animated: true)
    }

    func chatViewController(_ controller: ChatViewController, didTapEmote emote: Emote) {
        AppLogger.shared.debug("Tapped emote \(emote.name)", category: .ui)
    }

    func chatViewController(_ controller: ChatViewController, didTapLink url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = Theme.accent
        present(safari, animated: true)
    }

    func chatViewController(_ controller: ChatViewController, didRequestReplyTo message: ChatMessage) {
        controller.beginReply(to: message)
    }

    func chatViewControllerDidRequestLogin(_ controller: ChatViewController) {
        guard let anchor = view.window else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.auth.login(presentationAnchor: anchor)
            } catch {
                AppLogger.shared.warn("channel chat login failed: \(error)", category: .auth)
            }
        }
    }
}

@MainActor
private final class AudioOnlyBarView: UIView {
    var onPlayPause: (() -> Void)?
    var onRestoreVideo: (() -> Void)?

    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let titleLabel = UILabel()
    private let liveBadge = UIImageView()
    private let playPauseButton = UIButton(type: .system)
    private let restoreButton = UIButton(type: .system)

    init() {
        super.init(frame: .zero)
        isHidden = true
        backgroundColor = Theme.surface

        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 20
        avatarView.backgroundColor = Theme.surfaceElevated
        avatarView.image = UIImage(systemName: "person.crop.circle.fill")
        avatarView.tintColor = Theme.secondaryText

        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        nameLabel.textColor = Theme.primaryText

        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = Theme.secondaryText
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        let badgeConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        liveBadge.image = UIImage(systemName: "dot.radiowaves.left.and.right", withConfiguration: badgeConfig)
        liveBadge.tintColor = Theme.liveDot
        liveBadge.contentMode = .scaleAspectFit
        liveBadge.setContentHuggingPriority(.required, for: .horizontal)
        liveBadge.isAccessibilityElement = true
        liveBadge.accessibilityLabel = String(localized: "Live")

        let nameRow = UIStackView(arrangedSubviews: [nameLabel, liveBadge, UIView()])
        nameRow.axis = .horizontal
        nameRow.spacing = 6
        nameRow.alignment = .center

        let textStack = UIStackView(arrangedSubviews: [nameRow, titleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.lineBreakMode = .byTruncatingTail

        configureButton(playPauseButton, symbol: "pause.fill", label: String(localized: "Pause"))
        playPauseButton.addAction(UIAction { [weak self] _ in self?.onPlayPause?() }, for: .touchUpInside)
        configureButton(restoreButton, symbol: "play.rectangle.fill", label: String(localized: "Show Video"))
        restoreButton.addAction(UIAction { [weak self] _ in self?.onRestoreVideo?() }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [avatarView, textStack, playPauseButton, restoreButton])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 8)
        addSubview(row)

        let separator = UIView()
        separator.backgroundColor = Theme.surfaceElevated
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func configureButton(_ button: UIButton, symbol: String, label: String) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        config.baseForegroundColor = Theme.accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        button.configuration = config
        button.accessibilityLabel = label
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    func configure(name: String, title: String) {
        nameLabel.text = name
        titleLabel.text = title
    }

    func setAvatar(_ image: UIImage?) {
        guard let image else { return }
        avatarView.image = image
    }

    func setPlaying(_ playing: Bool) {
        var config = playPauseButton.configuration ?? .plain()
        config.image = UIImage(
            systemName: playing ? "pause.fill" : "play.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        )
        playPauseButton.configuration = config
        playPauseButton.accessibilityLabel = playing ? String(localized: "Pause") : String(localized: "Play")
        if playing, !Motion.reduced {
            liveBadge.addSymbolEffect(.variableColor.iterative, options: .repeating)
        } else {
            liveBadge.removeAllSymbolEffects()
        }
    }
}
