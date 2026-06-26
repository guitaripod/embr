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

    /// Shown only in immersive landscape, hosted above `chatOverlay` so it can both
    /// show and hide the floating chat (the embed's webview owns all other touches).
    private lazy var chatToggleButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        button.addAction(UIAction { [weak self] _ in self?.toggleFullscreenChat() }, for: .touchUpInside)
        return button
    }()

    init(channel: ChannelInfo, auth: AuthService = AuthService.shared, store: SettingsStore = .shared) {
        self.channel = channel
        self.auth = auth
        self.store = store
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        [.portrait, .landscapeLeft, .landscapeRight]
    }

    override var prefersStatusBarHidden: Bool { isLandscape }
    override var prefersHomeIndicatorAutoHidden: Bool { isLandscape }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(isLandscape, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = channel.broadcasterName
        navigationItem.largeTitleDisplayMode = .never
        isChatOnly = store.current.chatOnly ?? false
        navigationItem.rightBarButtonItems = [chatOnlyItem, videosItem]
        updateChatOnlyButton()
        setUpLayout()
        loadChildren()
        loadStreamInfo()
        observeAuth()
        WatchHistoryStore.shared.record(id: channel.id, login: channel.broadcasterLogin, name: channel.broadcasterName)
    }

    private func loadStreamInfo() {
        infoView.configure(channel: channel)
        gameToOpen = channel.gameName.isEmpty ? nil : GameCategory(id: channel.gameID, name: channel.gameName, boxArtURLTemplate: "")
        infoView.onTapGame = { [weak self] in
            guard let self, let game = self.gameToOpen else { return }
            self.navigationController?.pushViewController(TopViewController(mode: .game(game), api: AppContainer.shared.api), animated: true)
        }
        Task { [weak self] in
            guard let self else { return }
            guard let stream = try? await AppContainer.shared.api.streams(userIDs: [self.channel.id]).first else { return }
            self.infoView.configure(stream: stream)
            if !stream.gameName.isEmpty {
                self.gameToOpen = GameCategory(id: stream.gameID, name: stream.gameName, boxArtURLTemplate: "")
            }
        }
    }

    @objc private func toggleChatOnly() {
        setChatOnly(!isChatOnly)
    }

    private func updateChatOnlyButton() {
        chatOnlyItem.image = UIImage(systemName: isChatOnly ? "tv" : "bubble.left.and.bubble.right")
        chatOnlyItem.accessibilityLabel = isChatOnly ? "Show Video" : "Chat Only"
    }

    private func setChatOnly(_ on: Bool) {
        guard on != isChatOnly else { return }
        if isVideoFullscreen { setVideoFullscreen(false) }
        Haptics.selection(store)
        isChatOnly = on
        store.update { $0.chatOnly = on }
        updateChatOnlyButton()
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

        videoContainer.addSubview(chatToggleButton)

        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            containerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            chatToggleButton.topAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.topAnchor, constant: 6),
            chatToggleButton.trailingAnchor.constraint(equalTo: videoContainer.safeAreaLayoutGuide.trailingAnchor, constant: -8)
        ])

        applyOrientation(isLandscape: isLandscape)
    }

    private func applyOrientation(isLandscape landscape: Bool) {
        navigationController?.setNavigationBarHidden(landscape, animated: true)
        videoController?.setBackButtonHidden(navigationController != nil && !landscape)
        infoView.isHidden = landscape || isChatOnly
        if landscape {
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
            if !isChatOnly { applyPortraitVideoAspect() }
        }
        view.layoutIfNeeded()
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
        let immersive = fullscreen && !isChatOnly
        guard immersive != isVideoFullscreen, let chat = chatController else { return }
        isVideoFullscreen = immersive
        if immersive {
            installChatOverlay(chat: chat)
            updateChatToggleButton()
            chatToggleButton.isHidden = false
            videoContainer.bringSubviewToFront(chatToggleButton)
        } else {
            removeChatOverlay(chat: chat)
            chatToggleButton.isHidden = true
        }
        view.layoutIfNeeded()
    }

    private func updateChatToggleButton() {
        let symbol = fullscreenChatHidden ? "bubble.left.and.bubble.right" : "bubble.left.and.bubble.right.fill"
        chatToggleButton.configuration?.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        )
        chatToggleButton.accessibilityLabel = fullscreenChatHidden ? "Show Chat" : "Hide Chat"
    }

    private var fullscreenChatHidden = false

    @objc private func handleOverlayDoubleTap() {
        toggleFullscreenChat()
    }

    private func toggleFullscreenChat() {
        guard isVideoFullscreen else { return }
        fullscreenChatHidden.toggle()
        chatOverlay.isUserInteractionEnabled = !fullscreenChatHidden
        updateChatToggleButton()
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
