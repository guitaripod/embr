import UIKit
import Combine
import EmbrCore

@MainActor
final class VODViewController: UIViewController {
    private let vod: VideoOnDemand
    private let video: VideoViewController
    private let videoContainer = UIView()
    private let chatContainer = UIView()

    private var chat: ChatViewController?
    private var chatViewModel: ChatViewModel?
    private var layoutConstraints: [NSLayoutConstraint] = []
    private var isSideBySide = false
    private var isVideoFullscreen = false
    private var cancellables = Set<AnyCancellable>()

    private static let sideBySideMinimumWidth: CGFloat = 820

    init(vod: VideoOnDemand) {
        self.vod = vod
        self.video = VideoViewController(source: .vod(id: vod.id))
        super.init(nibName: nil, bundle: nil)
        title = vod.title
        hidesBottomBarWhenPushed = true
        navigationItem.largeTitleDisplayMode = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var channel: ChannelInfo {
        ChannelInfo(
            id: vod.userID,
            broadcasterLogin: vod.userLogin,
            broadcasterName: vod.userName,
            gameID: "",
            gameName: "",
            title: vod.title,
            language: "",
            tags: [],
            isLive: false
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        setUpVideo()
        setUpChatContainer()
        attachChat()
        updateLayout(force: true)
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (controller: VODViewController, _) in
            controller.updateLayout(force: true)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayout(force: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    private func setUpVideo() {
        videoContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoContainer)
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
        video.onProgress = { [weak self] progress in
            self?.chatViewModel?.setPlayback(seconds: progress.current)
        }
        video.onToggleFullscreen = { [weak self] in
            self?.toggleVideoFullscreen()
        }
    }

    private func setUpChatContainer() {
        chatContainer.translatesAutoresizingMaskIntoConstraints = false
        chatContainer.backgroundColor = Theme.background
        view.addSubview(chatContainer)
    }

    private func attachChat() {
        Task { [weak self] in
            guard let self else { return }
            let user = await AppContainer.shared.auth.currentUser()
            let loggedIn = user != nil
            let room = AppContainer.shared.makeChatRoom(
                channel: self.channel,
                loggedIn: loggedIn,
                mode: .vod(videoID: self.vod.id)
            )
            let viewModel = ChatViewModel(room: room, currentUserLogin: user?.login)
            let controller = ChatViewController(
                viewModel: viewModel,
                isAnonymous: !loggedIn,
                currentUserLogin: user?.login,
                broadcasterLogin: self.channel.broadcasterLogin,
                readOnly: true
            )
            self.chatViewModel = viewModel
            self.chat = controller
            self.addChild(controller)
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            self.chatContainer.addSubview(controller.view)
            NSLayoutConstraint.activate([
                controller.view.topAnchor.constraint(equalTo: self.chatContainer.topAnchor),
                controller.view.leadingAnchor.constraint(equalTo: self.chatContainer.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: self.chatContainer.trailingAnchor),
                controller.view.bottomAnchor.constraint(equalTo: self.chatContainer.bottomAnchor)
            ])
            controller.didMove(toParent: self)
        }
    }

    private func updateLayout(force: Bool) {
        let width = view.bounds.width
        guard width > 0 else { return }
        let sideBySide = !isVideoFullscreen && width >= Self.sideBySideMinimumWidth
        guard force || sideBySide != isSideBySide else { return }
        isSideBySide = sideBySide
        NSLayoutConstraint.deactivate(layoutConstraints)
        var constraints: [NSLayoutConstraint] = []

        if isVideoFullscreen {
            chatContainer.isHidden = true
            constraints += [
                videoContainer.topAnchor.constraint(equalTo: view.topAnchor),
                videoContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                videoContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                videoContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ]
        } else if sideBySide {
            chatContainer.isHidden = false
            constraints += [
                videoContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                videoContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                videoContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                chatContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                chatContainer.leadingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
                chatContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                chatContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                videoContainer.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.62)
            ]
        } else {
            chatContainer.isHidden = false
            let videoHeight = videoContainer.heightAnchor.constraint(equalTo: view.widthAnchor, multiplier: 9.0 / 16.0)
            videoHeight.priority = .defaultHigh
            constraints += [
                videoContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                videoContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                videoContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                videoHeight,
                videoContainer.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.55),
                videoContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
                chatContainer.topAnchor.constraint(equalTo: videoContainer.bottomAnchor),
                chatContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                chatContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                chatContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ]
        }
        layoutConstraints = constraints
        NSLayoutConstraint.activate(constraints)
        video.setImmersiveState(isVideoFullscreen)
    }

    private func toggleVideoFullscreen() {
        isVideoFullscreen.toggle()
        navigationController?.setNavigationBarHidden(isVideoFullscreen, animated: true)
        updateLayout(force: true)
    }
}
