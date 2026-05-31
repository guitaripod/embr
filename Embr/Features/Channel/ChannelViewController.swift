import UIKit
import Combine
import EmbrCore

@MainActor
final class ChannelViewController: UIViewController {
    private let channel: ChannelInfo
    private let auth: AuthService

    private var chatController: ChatViewController?

    private let containerStack = UIStackView()
    private let videoContainer = UIView()
    private let chatContainer = UIView()
    private let dividerHandle = UIView()

    private var cancellables = Set<AnyCancellable>()

    private var chatWidthFraction: CGFloat = 0.32
    private var landscapeWidthConstraint: NSLayoutConstraint?
    private lazy var dividerPan = UIPanGestureRecognizer(target: self, action: #selector(handleDividerPan(_:)))
    private var isVideoFullscreen = false
    private let chatOverlay = UIView()

    init(channel: ChannelInfo, auth: AuthService = AuthService.shared) {
        self.channel = channel
        self.auth = auth
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        [.portrait, .landscapeLeft, .landscapeRight]
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = channel.broadcasterName
        setUpLayout()
        loadChildren()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.applyOrientation(isLandscape: size.width > size.height)
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
        containerStack.addArrangedSubview(chatContainer)

        dividerHandle.translatesAutoresizingMaskIntoConstraints = false
        dividerHandle.backgroundColor = Theme.surfaceElevated
        dividerHandle.addGestureRecognizer(dividerPan)

        NSLayoutConstraint.activate([
            containerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            containerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerStack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        applyOrientation(isLandscape: isLandscape)
    }

    private func applyOrientation(isLandscape landscape: Bool) {
        if landscape {
            containerStack.axis = .horizontal
            installDivider()
            landscapeWidthConstraint?.isActive = false
            let constraint = chatContainer.widthAnchor.constraint(equalTo: containerStack.widthAnchor, multiplier: chatWidthFraction)
            constraint.isActive = true
            landscapeWidthConstraint = constraint
            videoContainer.removeConstraints(videoAspectConstraints)
            videoAspectConstraints = []
        } else {
            containerStack.axis = .vertical
            removeDivider()
            landscapeWidthConstraint?.isActive = false
            landscapeWidthConstraint = nil
            applyPortraitVideoAspect()
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
        guard fullscreen != isVideoFullscreen, let chat = chatController else { return }
        isVideoFullscreen = fullscreen
        if fullscreen {
            installChatOverlay(chat: chat)
        } else {
            removeChatOverlay(chat: chat)
        }
        view.layoutIfNeeded()
    }

    private func installChatOverlay(chat: ChatViewController) {
        chatContainer.isHidden = true
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
        let video = VideoViewController(source: .live(login: channel.broadcasterLogin))
        video.onFullscreenChange = { [weak self] fullscreen in
            self?.setVideoFullscreen(fullscreen)
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

        Task { [weak self] in
            guard let self else { return }
            let user = await self.auth.currentUser()
            self.attachChat(loggedIn: user != nil)
        }
    }

    private func attachChat(loggedIn: Bool) {
        let room = AppContainer.shared.makeChatRoom(channel: channel, loggedIn: loggedIn)
        let viewModel = ChatViewModel(room: room)
        let chat = ChatViewController(viewModel: viewModel, isAnonymous: !loggedIn)
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
    }
}

extension ChannelViewController: ChatViewControllerDelegate {
    func chatViewController(_ controller: ChatViewController, didTapUsername user: ChatUser) {
        AppLogger.shared.debug("Tapped username \(user.login)", category: .ui)
    }

    func chatViewController(_ controller: ChatViewController, didTapEmote emote: Emote) {
        AppLogger.shared.debug("Tapped emote \(emote.name)", category: .ui)
    }

    func chatViewController(_ controller: ChatViewController, didTapLink url: URL) {
        UIApplication.shared.open(url)
    }

    func chatViewController(_ controller: ChatViewController, didRequestReplyTo message: ChatMessage) {
        controller.beginReply(to: message)
    }
}
