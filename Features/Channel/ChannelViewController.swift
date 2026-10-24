import UIKit
import AuthenticationServices
import Combine
import EmbrCore
import SafariServices
import MidgarCore

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
    private let mainColumn = UIStackView()
    private let mainSpacer = UIView()
    private let foldGap = UIView()
    private var foldGapHeight: NSLayoutConstraint!
    private var videoHeightConstraint: NSLayoutConstraint?
    private let videoContainer = UIView()
    private let chatContainer = UIView()
    private let dividerHandle = ColumnDividerView()
    private let infoView = StreamInfoView()
    private let aboutView = ChannelAboutView()
    private var gameToOpen: GameCategory?

    /// How the page is arranged: video above chat, video beside a chat column (iPad, wide
    /// windows), or video filling the screen with chat floating over it.
    private enum Arrangement: Equatable {
        case stacked
        case sideBySide
        case immersive
    }

    private struct LayoutState: Equatable {
        var arrangement: Arrangement
        var showsInfo: Bool
        var hidesNavigationBar: Bool
        var hidesSystemChrome: Bool
        var showsOverlayBackButton: Bool
        var centersChatColumn: Bool
        var fold: FoldRegion?
    }

    private static let sideBySideMinimumWidth: CGFloat = 600
    private static let minimumFoldColumn: CGFloat = 240
    private static let chatColumnWidthKey = "channel.chatColumnWidth"
    private static let chatColumnMaximumWidth: CGFloat = 720

    private var appliedLayout: LayoutState?
    private var isApplyingLayout = false
    private var prefersFullscreen = false
    private var edgeConstraints: [NSLayoutConstraint] = []
    private var safeAreaEdgeConstraints: [NSLayoutConstraint] = []
    private var centeredColumnConstraints: [NSLayoutConstraint] = []
    private var chatWidthConstraint: NSLayoutConstraint?
    private var chatColumnWidth: CGFloat = {
        let stored = UserDefaults.standard.double(forKey: chatColumnWidthKey)
        return stored > 0 ? CGFloat(stored) : 0
    }()
    private var dividerStartWidth: CGFloat = 0
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

    var broadcasterID: String { channel.id }

    var player: VideoViewController? { videoController }

    /// Single-key shortcuts stand down while the viewer types a chat message.
    var isTypingInChat: Bool { chatController?.isComposing ?? false }

    func toggleFavoriteFromCommand() {
        toggleFavorite()
    }

    private var reviewWatchWork: DispatchWorkItem?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        OrientationCoordinator.isPhone ? [.portrait, .landscapeLeft, .landscapeRight] : .all
    }

    override var prefersStatusBarHidden: Bool { currentLayout.hidesSystemChrome }
    override var prefersHomeIndicatorAutoHidden: Bool { currentLayout.hidesSystemChrome }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    private var currentLayout: LayoutState {
        appliedLayout ?? layoutState(for: view.bounds.size)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        scheduleReviewWatchSuccess()
        navigationController?.setNavigationBarHidden(currentLayout.hidesNavigationBar, animated: animated)
        (tabBarController as? RootTabBarController)?.beginPlayback()
        eventsPoller.start()
        liveStatsPoller.start()
        eventCard.resume()
    }

    /// Stage Manager and the app switcher label the window with the channel being watched.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.window?.windowScene?.title = channel.broadcasterName
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        view.window?.windowScene?.title = nil
        cancelReviewWatchSuccess()
        navigationController?.setNavigationBarHidden(false, animated: animated)
        if isMovingFromParent {
            (tabBarController as? RootTabBarController)?.endPlayback()
        }
        eventsPoller.stop()
        liveStatsPoller.stop()
        eventCard.pause()
    }

    /// Credits a review-prompt success once this visit has stayed on a confirmed live stream
    /// continuously for `ReviewPrompt.continuousWatchSecondsForSuccess`; leaving before then, or
    /// never getting a positive live confirmation (an offline channel, or a run of failed polls),
    /// earns nothing.
    private func scheduleReviewWatchSuccess() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hasConfirmedLiveStream, !self.isStreamOffline else { return }
            ReviewPrompt.recordStreamWatched(in: self.view.window?.windowScene)
        }
        reviewWatchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + ReviewPrompt.continuousWatchSecondsForSuccess, execute: work)
    }

    private func cancelReviewWatchSuccess() {
        reviewWatchWork?.cancel()
        reviewWatchWork = nil
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
        if let keyboard = ScreenshotRouter.option("Keyboard") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                self?.chatController?.raiseKeyboardForScreenshot(emotes: keyboard == "emotes")
            }
        }
        let pose = ScreenshotHarness.channelPose
        guard pose != .normal else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            switch pose {
            case .audio: self.videoController?.setAudioOnly(true)
            case .chat: self.setChatOnly(true)
            case .fullscreen: self.videoController?.toggleFullscreen()
            case .fullscreenChat:
                self.videoController?.toggleFullscreen()
                if !self.isFullscreenChatVisible { self.toggleFullscreenChat() }
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
            let user = try? await AppContainer.shared.api.users(ids: [self.channel.id]).first
            self.avatarURL = user?.profileImageURL
            if let user {
                self.aboutView.configure(user: user)
                self.updateAboutVisibility()
            }
            if let stream = try? await AppContainer.shared.api.streams(userIDs: [self.channel.id]).first {
                self.applyLiveStream(stream)
            } else {
                self.applyMetadata(title: self.channel.title)
            }
            if let avatarURL = self.avatarURL,
               let image = await ImageLoader.shared.image(for: avatarURL, targetScale: 2.0) {
                self.audioBar.setAvatar(image)
                self.aboutView.setAvatar(image)
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
    private var hasConfirmedLiveStream = false
    private var lastAppliedTitle: String?

    private func applyLiveStream(_ stream: LiveStream) {
        isStreamOffline = false
        hasConfirmedLiveStream = true
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
        prefersFullscreen = false
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
        applyLayout()
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
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.applyLayout(for: size)
        })
    }

    /// Window resizes on iPad do not all arrive as transitions, so the arrangement is also
    /// rechecked whenever the page lays out at a size that calls for a different one.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateAboutVisibility()
        guard !isApplyingLayout, appliedLayout != nil, layoutState(for: view.bounds.size) != appliedLayout else { return }
        applyLayout(for: view.bounds.size)
    }

    /// The About card appears only when the side-by-side layout leaves room for all of it under
    /// the stream details; it never takes height from the video.
    private func updateAboutVisibility() {
        let width = mainColumn.bounds.width
        var fits = false
        if currentLayout.arrangement == .sideBySide, aboutView.hasContent, width > 0 {
            let target = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
            let info = infoView.systemLayoutSizeFitting(target, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
            let about = aboutView.systemLayoutSizeFitting(target, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
            let video = isVideoShown ? width * 9 / 16 : 0
            fits = video + info + about <= mainColumn.bounds.height
        }
        if aboutView.isHidden == fits {
            aboutView.isHidden = !fits
        }
    }

    private var isVideoShown: Bool { !isChatOnly && !isAudioOnly }

    /// A phone-sized window keeps the phone rule: portrait stacks video over chat, landscape goes
    /// fullscreen. Windows with room for it (every iPad window, the inner display of a foldable
    /// phone) get video beside a chat column once they are wide enough, and go fullscreen only when
    /// asked. A partly folded device adds the fold to the state, so the columns divide on it.
    private func layoutState(for size: CGSize) -> LayoutState {
        let landscape = size.width > size.height
        if !OrientationCoordinator.usesTabletLayout(for: size) {
            let immersive = landscape && isVideoShown
            return LayoutState(
                arrangement: immersive ? .immersive : .stacked,
                showsInfo: !landscape && isVideoShown,
                hidesNavigationBar: landscape && !isAudioOnly,
                hidesSystemChrome: landscape,
                showsOverlayBackButton: landscape || navigationController == nil,
                centersChatColumn: false,
                fold: nil
            )
        }
        let fold = isViewLoaded ? Fold.region(in: view) : nil
        let arrangement: Arrangement
        var automaticFullscreen = false
        let detailsBesideChat = isChatOnly && !isAudioOnly && fold.map(Self.isVertical) == true
            && landscape && size.width >= Self.sideBySideMinimumWidth
        if detailsBesideChat {
            arrangement = .sideBySide
        } else if !isVideoShown {
            arrangement = .stacked
        } else if prefersFullscreen {
            arrangement = .immersive
        } else if landscape, size.width >= Self.sideBySideMinimumWidth {
            arrangement = .sideBySide
        } else if landscape {
            arrangement = .immersive
            automaticFullscreen = true
        } else {
            arrangement = .stacked
        }
        var foldInUse: FoldRegion?
        switch (fold, arrangement) {
        case (.vertical?, .sideBySide), (.horizontal?, .stacked): foldInUse = fold
        default: foldInUse = nil
        }
        return LayoutState(
            arrangement: arrangement,
            showsInfo: (isVideoShown || detailsBesideChat) && arrangement != .immersive,
            hidesNavigationBar: arrangement == .immersive,
            hidesSystemChrome: arrangement == .immersive,
            showsOverlayBackButton: automaticFullscreen || navigationController == nil,
            centersChatColumn: !isVideoShown && size.width > Self.chatColumnMaximumWidth + 40 && foldInUse == nil,
            fold: foldInUse
        )
    }

    private static func isVertical(_ fold: FoldRegion) -> Bool {
        if case .vertical = fold { return true }
        return false
    }

    private func setUpLayout() {
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        containerStack.alignment = .fill
        containerStack.distribution = .fill
        view.addSubview(containerStack)

        videoContainer.translatesAutoresizingMaskIntoConstraints = false
        videoContainer.backgroundColor = .black
        chatContainer.translatesAutoresizingMaskIntoConstraints = false
        chatContainer.backgroundColor = Theme.background
        infoView.setContentCompressionResistancePriority(.required, for: .vertical)
        mainSpacer.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        mainSpacer.isHidden = true
        foldGap.translatesAutoresizingMaskIntoConstraints = false
        foldGap.isHidden = true
        foldGapHeight = foldGap.heightAnchor.constraint(equalToConstant: 0)
        foldGapHeight.isActive = true

        mainColumn.axis = .vertical
        mainColumn.alignment = .fill
        mainColumn.distribution = .fill
        mainColumn.addArrangedSubview(videoContainer)
        mainColumn.addArrangedSubview(foldGap)
        mainColumn.addArrangedSubview(infoView)
        mainColumn.addArrangedSubview(aboutView)
        mainColumn.addArrangedSubview(mainSpacer)
        aboutView.isHidden = true
        aboutView.onShowVideos = { [weak self] in
            self?.showVideos()
        }

        containerStack.addArrangedSubview(mainColumn)
        containerStack.addArrangedSubview(chatContainer)

        dividerHandle.translatesAutoresizingMaskIntoConstraints = false
        dividerHandle.addGestureRecognizer(dividerPan)
        dividerHandle.onAccessibilityAdjust = { [weak self] delta in
            self?.adjustChatColumn(by: delta)
        }

        chatOverlay.addGestureRecognizer(chatOverlayDoubleTap)

        let safeArea = view.safeAreaLayoutGuide
        edgeConstraints = [
            containerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ]
        safeAreaEdgeConstraints = [
            containerStack.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            containerStack.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor)
        ]
        let fullWidth = containerStack.widthAnchor.constraint(equalTo: safeArea.widthAnchor)
        fullWidth.priority = .defaultHigh
        centeredColumnConstraints = [
            containerStack.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            containerStack.widthAnchor.constraint(lessThanOrEqualToConstant: Self.chatColumnMaximumWidth),
            containerStack.widthAnchor.constraint(lessThanOrEqualTo: safeArea.widthAnchor),
            fullWidth
        ]
        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: safeArea.topAnchor),
            containerStack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        Fold.relayout(view)
        applyLayout()
    }

    private func applyLayout(for size: CGSize? = nil) {
        let size = size ?? view.bounds.size
        let state = layoutState(for: size)
        isApplyingLayout = true
        defer { isApplyingLayout = false }
        appliedLayout = state

        navigationController?.setNavigationBarHidden(state.hidesNavigationBar, animated: true)
        videoController?.setBackButtonHidden(!state.showsOverlayBackButton)
        videoContainer.isHidden = !isVideoShown
        infoView.isHidden = !state.showsInfo
        if state.arrangement != .sideBySide { aboutView.isHidden = true }
        mainSpacer.isHidden = state.arrangement != .sideBySide
        mainColumn.isHidden = !isVideoShown && state.arrangement != .sideBySide
        containerStack.axis = state.arrangement == .stacked ? .vertical : .horizontal

        applyContainerEdges(state)
        applyVideoSizing(state)
        applyChatColumn(state, width: size.width)
        applyFold(state)
        applyImmersive(state.arrangement == .immersive)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        view.layoutIfNeeded()
    }

    /// Content keeps clear of the sidebar, window controls and a foldable phone's side bar through
    /// the safe area; fullscreen video runs edge to edge; chat alone on a wide window is centered
    /// at a readable width.
    private func applyContainerEdges(_ state: LayoutState) {
        NSLayoutConstraint.deactivate(edgeConstraints + safeAreaEdgeConstraints + centeredColumnConstraints)
        if state.centersChatColumn {
            NSLayoutConstraint.activate(centeredColumnConstraints)
        } else if state.arrangement != .immersive {
            NSLayoutConstraint.activate(safeAreaEdgeConstraints)
        } else {
            NSLayoutConstraint.activate(edgeConstraints)
        }
    }

    /// Stacked, the video is exactly 16:9 across the width. Beside the chat column it may give
    /// up height so the stream details below it stay on screen; the player letterboxes.
    private func applyVideoSizing(_ state: LayoutState) {
        videoContainer.removeConstraints(videoAspectConstraints)
        videoAspectConstraints = []
        guard isVideoShown, state.arrangement != .immersive else { return }
        let aspect = videoContainer.heightAnchor.constraint(equalTo: videoContainer.widthAnchor, multiplier: 9.0 / 16.0)
        aspect.priority = state.arrangement == .sideBySide || state.fold != nil ? UILayoutPriority(740) : .required
        aspect.isActive = true
        videoAspectConstraints = [aspect]
    }

    /// Divides the page on the fold. Beside a vertical fold the video column ends where the fold
    /// begins and the chat column starts where it ends, so nothing sits on the crease. Above a
    /// horizontal fold the video keeps to the top region and everything under it, the stream
    /// details, chat and the message field, starts below the crease.
    private func applyFold(_ state: LayoutState) {
        foldGapHeight.constant = 0
        foldGap.isHidden = true
        containerStack.spacing = 0
        videoHeightConstraint?.isActive = false
        videoHeightConstraint = nil
        guard let fold = state.fold else { return }
        let insets = view.safeAreaInsets
        switch fold {
        case .vertical(let minX, let maxX):
            let chatWidth = view.bounds.width - insets.right - maxX
            guard chatWidth >= Self.minimumFoldColumn, minX - insets.left >= Self.minimumFoldColumn else { return }
            containerStack.spacing = maxX - minX
            chatWidthConstraint?.constant = chatWidth
            removeDivider()
        case .horizontal(let minY, let maxY):
            guard isVideoShown else { return }
            let available = minY - insets.top
            guard available >= Self.minimumFoldColumn / 2 else { return }
            let width = view.bounds.width - insets.left - insets.right
            let videoHeight = min(width * 9.0 / 16.0, available)
            let cap = videoContainer.heightAnchor.constraint(lessThanOrEqualToConstant: available)
            cap.isActive = true
            videoHeightConstraint = cap
            foldGapHeight.constant = max(0, maxY - (insets.top + videoHeight))
            foldGap.isHidden = false
        }
    }

    private func applyChatColumn(_ state: LayoutState, width: CGFloat) {
        chatWidthConstraint?.isActive = false
        chatWidthConstraint = nil
        guard state.arrangement == .sideBySide else {
            removeDivider()
            return
        }
        let constraint = chatContainer.widthAnchor.constraint(equalToConstant: clampedChatWidth(chatColumnWidth, windowWidth: width))
        constraint.isActive = true
        chatWidthConstraint = constraint
        installDivider()
    }

    /// The chat column starts near a third of the window, and whatever width the reader drags
    /// it to is kept for the next channel, within bounds that leave the video usable.
    private func clampedChatWidth(_ proposed: CGFloat, windowWidth: CGFloat) -> CGFloat {
        let preferred = proposed > 0 ? proposed : windowWidth * 0.3
        let maximum = max(280, min(560, windowWidth - 320))
        return min(maximum, max(280, preferred))
    }

    /// Collapses the video area to a compact audio bar (chat fills the screen) or
    /// restores the full video layout. Session-only: the layout is forced vertical
    /// while audio-only so chat stays primary in both orientations.
    private func applyAudioOnly(_ on: Bool) {
        guard on != isAudioOnly else { return }
        prefersFullscreen = false
        isAudioOnly = on
        Haptics.selection(store)
        if on {
            if audioBar.superview == nil {
                containerStack.insertArrangedSubview(audioBar, at: 0)
            }
            audioBar.isHidden = false
        } else {
            audioBar.isHidden = true
            audioBar.removeFromSuperview()
        }
        applyLayout()
    }

    private var videoAspectConstraints: [NSLayoutConstraint] = []

    private func installDivider() {
        guard dividerHandle.superview == nil else { return }
        view.addSubview(dividerHandle)
        NSLayoutConstraint.activate([
            dividerHandle.topAnchor.constraint(equalTo: containerStack.topAnchor),
            dividerHandle.bottomAnchor.constraint(equalTo: containerStack.bottomAnchor),
            dividerHandle.centerXAnchor.constraint(equalTo: chatContainer.leadingAnchor),
            dividerHandle.widthAnchor.constraint(equalToConstant: ColumnDividerView.hitWidth)
        ])
    }

    private func removeDivider() {
        dividerHandle.removeFromSuperview()
    }

    @objc private func handleDividerPan(_ recognizer: UIPanGestureRecognizer) {
        guard currentLayout.arrangement == .sideBySide, let constraint = chatWidthConstraint else { return }
        switch recognizer.state {
        case .began:
            dividerStartWidth = constraint.constant
            dividerHandle.setDragging(true)
        case .changed:
            let proposed = dividerStartWidth - recognizer.translation(in: view).x
            constraint.constant = clampedChatWidth(proposed, windowWidth: view.bounds.width)
            view.layoutIfNeeded()
        default:
            dividerHandle.setDragging(false)
            chatColumnWidth = constraint.constant
            UserDefaults.standard.set(Double(chatColumnWidth), forKey: Self.chatColumnWidthKey)
        }
    }

    private func adjustChatColumn(by delta: CGFloat) {
        guard let constraint = chatWidthConstraint else { return }
        constraint.constant = clampedChatWidth(constraint.constant + delta, windowWidth: view.bounds.width)
        chatColumnWidth = constraint.constant
        UserDefaults.standard.set(Double(chatColumnWidth), forKey: Self.chatColumnWidthKey)
        UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
    }

    /// iPad fullscreen: the video takes the whole window and chat floats over it on demand.
    /// The phone reaches fullscreen by turning to landscape instead.
    func toggleFullscreen() {
        guard OrientationCoordinator.usesTabletLayout(for: view.bounds.size), isVideoShown else { return }
        prefersFullscreen.toggle()
        Haptics.selection(store)
        let animations = { self.applyLayout() }
        if Motion.reduced {
            animations()
        } else {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut], animations: animations)
        }
    }

    var isFullscreen: Bool { isVideoFullscreen }

    var isFullscreenChatVisible: Bool { isVideoFullscreen && !fullscreenChatHidden }

    func exitFullscreen() {
        guard prefersFullscreen else { return }
        toggleFullscreen()
    }

    private func applyImmersive(_ immersive: Bool) {
        videoController?.setImmersiveState(immersive)
        guard immersive != isVideoFullscreen, let chat = chatController else { return }
        isVideoFullscreen = immersive
        if immersive {
            installChatOverlay(chat: chat)
        } else {
            removeChatOverlay(chat: chat)
        }
    }

    private var fullscreenChatHidden = false

    @objc private func handleOverlayDoubleTap() {
        toggleFullscreenChat()
    }

    func toggleFullscreenChat() {
        guard isVideoFullscreen else { return }
        fullscreenChatHidden.toggle()
        chatOverlay.isUserInteractionEnabled = !fullscreenChatHidden
        Haptics.impact(.light)
        UIView.animate(withDuration: 0.25) {
            self.chatOverlay.alpha = self.fullscreenChatHidden ? 0 : 1
        }
    }

    /// Fullscreen chat floats over the right of the video. The phone shows it at once, since
    /// turning sideways is how phone viewers watch with chat; an iPad asked for fullscreen
    /// shows the video alone until chat is called up.
    private func installChatOverlay(chat: ChatViewController) {
        chatContainer.isHidden = true
        fullscreenChatHidden = OrientationCoordinator.usesTabletLayout(for: view.bounds.size)
        chatOverlay.alpha = fullscreenChatHidden ? 0 : 1
        chatOverlay.isUserInteractionEnabled = !fullscreenChatHidden
        chatOverlay.translatesAutoresizingMaskIntoConstraints = false
        chatOverlay.backgroundColor = Theme.background.withAlphaComponent(0.35)
        videoContainer.addSubview(chatOverlay)
        chat.view.removeFromSuperview()
        chatOverlay.addSubview(chat.view)
        NSLayoutConstraint.activate([
            chatOverlay.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            chatOverlay.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),
            chatOverlay.trailingAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.trailingAnchor),
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
        video.onToggleFullscreen = { [weak self] in
            self?.toggleFullscreen()
        }
        video.hostImmersiveState = { [weak self] in
            self?.isVideoFullscreen ?? false
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
        video.setBackButtonHidden(!currentLayout.showsOverlayBackButton)

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
        applyImmersive(currentLayout.arrangement == .immersive)
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
        MidgarLog.debug("Tapped emote \(emote.name)", category: .ui)
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
                LiveAlertsPrompt.offerAfterSignIn(from: self)
            } catch {
                MidgarLog.notice("channel chat login failed: \(error)", category: .auth)
            }
        }
    }
}
