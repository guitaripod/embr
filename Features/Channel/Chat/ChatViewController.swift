import UIKit
import AudioToolbox
import Combine
import EmbrCore
import MidgarCore

@MainActor
protocol ChatViewControllerDelegate: AnyObject {
    func chatViewController(_ controller: ChatViewController, didTapUsername user: ChatUser)
    func chatViewController(_ controller: ChatViewController, didTapEmote emote: Emote)
    func chatViewController(_ controller: ChatViewController, didTapLink url: URL)
    func chatViewController(_ controller: ChatViewController, didRequestReplyTo message: ChatMessage)
    func chatViewControllerDidRequestLogin(_ controller: ChatViewController)
}

@MainActor
final class ChatViewController: UIViewController {
    weak var delegate: ChatViewControllerDelegate?

    private let viewModel: ChatViewModel
    private let images: ImageLoading
    private let isAnonymous: Bool
    private let isReadOnly: Bool
    private let currentUserLogin: String?
    private let broadcasterLogin: String?
    private var canModerate = false
    private let animator = EmoteAnimator.shared

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, ChatRow>!
    private lazy var composer = ChatInputView(images: images)
    private lazy var guestBar = GuestChatBar()
    private let statusBar = ConnectionStatusBar()
    private let newMessagesPill = NewMessagesPill()
    private let moderationBar = ModerationBar()
    private var moderationBarHeight: NSLayoutConstraint?
    private let searchField = UISearchTextField()
    private let emptyLabel = UILabel()

    private var cancellables = Set<AnyCancellable>()
    private var isPaused = false
    private var lastContentOffsetY: CGFloat = 0
    private var fastScroll = false

    private var catalog = EmoteCatalog()
    private var chatterIndex: [String: String] = [:]
    private static let chatterIndexCap = 2000
    private var lastLayoutWidth: CGFloat = 0
    private var lastHighlightAlert = Date.distantPast

    init(
        viewModel: ChatViewModel,
        images: ImageLoading = AppContainer.shared.images,
        isAnonymous: Bool,
        currentUserLogin: String? = nil,
        broadcasterLogin: String? = nil,
        readOnly: Bool = false
    ) {
        self.viewModel = viewModel
        self.images = images
        self.isAnonymous = isAnonymous
        self.isReadOnly = readOnly
        self.currentUserLogin = currentUserLogin
        self.broadcasterLogin = broadcasterLogin
        super.init(nibName: nil, bundle: nil)
        if !readOnly, !isAnonymous, let me = currentUserLogin?.lowercased(), me == broadcasterLogin?.lowercased() {
            canModerate = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        setUpCollectionView()
        setUpDataSource()
        setUpOverlays()
        setUpInput()
        setUpReconnectObservers()
        bind()
        viewModel.start()
    }

    private func setUpReconnectObservers() {
        statusBar.onTapReconnect = { [weak self] in
            Haptics.selection()
            self?.viewModel.wake()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleForegroundWake),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
        NetworkMonitor.shared.restored
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.viewModel.wake() }
            .store(in: &cancellables)
    }

    @objc private func handleForegroundWake() {
        viewModel.wake()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !isAnonymous && !isReadOnly { composer.setEmoteKeyboardPageLeading(foldPageLeading) }
        let width = collectionView.bounds.width
        guard width > 0, width != lastLayoutWidth else { return }
        lastLayoutWidth = width
        viewModel.updateWidth(width)
        collectionView.collectionViewLayout.invalidateLayout()
    }

    /// Where the page this chat is on begins when the device is open like a book and the chat sits
    /// on the page after the fold; zero when there is no fold or the chat does not start beyond it.
    private var foldPageLeading: CGFloat {
        guard let window = view.window, case .vertical(_, let maxX)? = Fold.region(in: window),
              view.convert(view.bounds, to: window).minX >= maxX - 1 else { return 0 }
        return maxX
    }

    func endSession() {
        viewModel.stop()
    }

    #if DEBUG
    /// Opens the moderator's queue, for a screenshot.
    func presentModerationQueueForScreenshot() {
        presentModerationQueue()
    }

    /// Opens the card of whoever wrote the newest message, or of the named chatter, for a screenshot.
    func presentUserCardForScreenshot(login: String?) {
        let me = currentUserLogin?.lowercased()
        let pick = dataSource.snapshot().itemIdentifiers.first { row in
            let author = row.message.author.login.lowercased()
            return login.map { author == $0.lowercased() } ?? (author != me)
        }
        guard let row = pick else { return }
        canModerate = canModerate || ScreenshotHarness.moderates
        presentUserCard(for: row.message.author, message: row.message)
    }

    /// Brings up the system keyboard, or the emote keyboard, for a screenshot of the composer.
    func raiseKeyboardForScreenshot(emotes: Bool) {
        guard !isAnonymous else { return }
        if emotes {
            composer.showEmoteKeyboardForScreenshot()
        } else {
            _ = composer.becomeFirstResponder()
        }
    }
    #endif

    var isComposing: Bool {
        !isAnonymous && !isReadOnly && composer.isEditing
    }

    func routeUsernameTap(_ user: ChatUser) {
        delegate?.chatViewController(self, didTapUsername: user)
    }

    func routeEmoteTap(_ emote: Emote) {
        delegate?.chatViewController(self, didTapEmote: emote)
    }

    func routeLinkTap(_ url: URL) {
        delegate?.chatViewController(self, didTapLink: url)
    }

    private func setUpCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.transform = CGAffineTransform(scaleX: 1, y: -1)
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.contentInsetAdjustmentBehavior = .scrollableAxes
        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboardOnTap))
        dismissTap.cancelsTouchesInView = false
        dismissTap.delegate = self
        collectionView.addGestureRecognizer(dismissTap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleMessageLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        longPress.delegate = self
        collectionView.addGestureRecognizer(longPress)

        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setUpDataSource() {
        let registration = UICollectionView.CellRegistration<MessageCell, ChatRow> { [weak self] cell, _, row in
            guard let self else { return }
            if let laidOut = row.laidOut {
                cell.configure(with: laidOut, message: row.message, images: self.images, animator: self.animator)
            }
            cell.onTapUser = { [weak self] user in
                self?.presentUserCard(for: user, message: row.message)
            }
            cell.onTapEmote = { [weak self] emote in
                guard let self else { return }
                self.delegate?.chatViewController(self, didTapEmote: emote)
            }
            cell.onTapLink = { [weak self] url in
                guard let self else { return }
                self.delegate?.chatViewController(self, didTapLink: url)
            }
            cell.onSwipeReply = self.isAnonymous ? nil : { [weak self] in
                guard let self else { return }
                self.delegate?.chatViewController(self, didRequestReplyTo: row.message)
            }
            cell.onShowActions = { [weak self, weak cell] in
                guard let self else { return }
                let sourceRect = cell.map { self.view.convert($0.bounds, from: $0) } ?? .zero
                self.presentMessageActions(for: row.message, sourceRect: sourceRect)
            }
        }
        dataSource = UICollectionViewDiffableDataSource<Int, ChatRow>(collectionView: collectionView) { collectionView, indexPath, row in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: row)
        }
    }

    private func setUpOverlays() {
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = isReadOnly
            ? String(localized: "Loading chat replay…")
            : String(localized: "Waiting for messages…")
        emptyLabel.font = .systemFont(ofSize: 14, weight: .regular)
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.textAlignment = .center
        view.insertSubview(emptyLabel, belowSubview: collectionView)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.isHidden = true
        view.addSubview(statusBar)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = String(localized: "Search chat")
        searchField.isHidden = true
        searchField.returnKeyType = .search
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        view.addSubview(searchField)

        newMessagesPill.translatesAutoresizingMaskIntoConstraints = false
        newMessagesPill.isHidden = true
        newMessagesPill.onTap = { [weak self] in self?.jumpToLatest() }
        view.addSubview(newMessagesPill)

        NSLayoutConstraint.activate([
            statusBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            searchField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),

            newMessagesPill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            newMessagesPill.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor, constant: -12)
        ])

        view.bringSubviewToFront(statusBar)
    }

    private func setUpInput() {
        if isReadOnly {
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
            return
        }
        guard !isAnonymous else {
            setUpGuestBar()
            return
        }
        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.delegate = self
        view.addSubview(composer)

        moderationBar.translatesAutoresizingMaskIntoConstraints = false
        moderationBar.isHidden = true
        moderationBar.onOpen = { [weak self] in self?.presentModerationQueue() }
        view.addSubview(moderationBar)
        let barHeight = moderationBar.heightAnchor.constraint(equalToConstant: 0)
        moderationBarHeight = barHeight

        view.keyboardLayoutGuide.usesBottomSafeArea = false
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            moderationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            moderationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            moderationBar.bottomAnchor.constraint(equalTo: composer.topAnchor),
            barHeight,
            collectionView.bottomAnchor.constraint(equalTo: moderationBar.topAnchor)
        ])
    }

    private func setUpGuestBar() {
        guestBar.translatesAutoresizingMaskIntoConstraints = false
        guestBar.onLogin = { [weak self] in
            guard let self else { return }
            self.delegate?.chatViewControllerDidRequestLogin(self)
        }
        view.addSubview(guestBar)
        NSLayoutConstraint.activate([
            guestBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            guestBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            guestBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            collectionView.bottomAnchor.constraint(equalTo: guestBar.topAnchor)
        ])
    }

    private func bind() {
        viewModel.snapshotSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                MainActor.assumeIsolated { self?.apply(snapshot) }
            }
            .store(in: &cancellables)

        viewModel.connectionSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated { self?.statusBar.update(status) }
            }
            .store(in: &cancellables)

        viewModel.roomStateSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.statusBar.update(roomState: state)
                    if !self.isAnonymous { self.composer.setRoomState(state) }
                }
            }
            .store(in: &cancellables)

        viewModel.catalogSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] catalog in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.catalog = catalog
                    if !self.isAnonymous { self.composer.setCatalog(catalog) }
                }
            }
            .store(in: &cancellables)

        viewModel.noticeSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notice in
                MainActor.assumeIsolated { self?.statusBar.showNotice(notice) }
            }
            .store(in: &cancellables)
        viewModel.moderationSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] queue in
                MainActor.assumeIsolated { self?.showModeration(queue) }
            }
            .store(in: &cancellables)
        viewModel.replay()
        confirmModeratorStatus()
    }

    /// Turns on moderator actions where Twitch lists the viewer as a moderator, before they have said anything here.
    private func confirmModeratorStatus() {
        guard !canModerate, !isAnonymous, !isReadOnly else { return }
        Task { [weak self] in
            guard let self else { return }
            let channelID = await self.viewModel.channelID
            if await ModerationAccess.shared.moderates(channelID) { self.canModerate = true }
        }
    }

    private func showModeration(_ queue: ModerationQueue) {
        guard !isAnonymous, !isReadOnly else { return }
        let shows = !queue.isEmpty
        moderationBar.show(held: queue.held.count, requests: queue.requests.count, logged: queue.log.count)
        guard shows == moderationBar.isHidden else { return }
        moderationBar.isHidden = !shows
        moderationBarHeight?.constant = shows ? ModerationBar.height : 0
        UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
    }

    private func presentModerationQueue() {
        Haptics.selection()
        let queue = viewModel.moderation
        let controller = ModerationQueueViewController(viewModel: viewModel, startingWithLog: queue.held.isEmpty && queue.requests.isEmpty)
        let navigation = UINavigationController(rootViewController: controller)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(navigation, animated: true)
    }

    private func apply(_ snapshot: ChatSnapshot) {
        isPaused = snapshot.isPaused
        emptyLabel.isHidden = !snapshot.rows.isEmpty
        if chatterIndex.count > Self.chatterIndexCap * 2 {
            chatterIndex.removeAll(keepingCapacity: true)
        }
        for row in snapshot.rows {
            chatterIndex[row.message.author.login.lowercased()] = row.message.author.displayName
        }
        detectModeratorIfNeeded(snapshot.rows)

        var diff = NSDiffableDataSourceSnapshot<Int, ChatRow>()
        diff.appendSections([0])
        diff.appendItems(snapshot.rows.reversed(), toSection: 0)
        let shouldStickToBottom = !snapshot.isPaused
        let finish = { [weak self] in
            guard let self, shouldStickToBottom else { return }
            self.scrollToLatest(animated: false)
        }
        if snapshot.relayout {
            dataSource.applySnapshotUsingReloadData(diff, completion: finish)
        } else {
            dataSource.apply(diff, animatingDifferences: false, completion: finish)
        }

        if snapshot.isPaused, snapshot.newCount > 0 {
            newMessagesPill.setCount(snapshot.newCount)
            newMessagesPill.isHidden = false
        } else {
            newMessagesPill.isHidden = true
        }
        if snapshot.alerts > 0 { alertHighlight() }
    }

    /// A haptic and, when the viewer asked for it, a short sound for a message that stands out for them: only while
    /// this chat is on screen and Embr is in front, and at most once every two seconds in a busy chat.
    private func alertHighlight() {
        guard view.window != nil, UIApplication.shared.applicationState == .active,
              Date().timeIntervalSince(lastHighlightAlert) > 2 else { return }
        lastHighlightAlert = Date()
        let settings = SettingsStore.shared.current
        if settings.highlightHapticEnabled { Haptics.notify(.warning) }
        if settings.highlightSoundEnabled { AudioServicesPlaySystemSound(Self.highlightSound) }
    }

    private static let highlightSound: SystemSoundID = 1057

    /// Opens a chatter's card for their name in a message, or from the message's actions.
    func presentUserCard(for user: ChatUser, message: ChatMessage?) {
        Haptics.selection()
        let isSelf = user.login.lowercased() == currentUserLogin?.lowercased()
        let card = ChatUserCardViewController(
            context: ChatUserCardViewController.Context(
                user: user,
                message: message,
                channelLogin: broadcasterLogin,
                canChat: !isAnonymous && !isReadOnly,
                canModerate: canModerate && user.login.lowercased() != broadcasterLogin?.lowercased(),
                isSelf: isSelf
            ),
            viewModel: viewModel
        )
        card.onMention = { [weak self] user in
            guard let self else { return }
            self.composer.insertMention(user.login)
            _ = self.composer.becomeFirstResponder()
        }
        card.onOpenProfile = { [weak self] user in
            guard let self else { return }
            self.delegate?.chatViewController(self, didTapUsername: user)
        }
        present(card, animated: true)
    }

    private func scrollToLatest(animated: Bool) {
        guard collectionView.numberOfSections > 0, collectionView.numberOfItems(inSection: 0) > 0 else { return }
        collectionView.setContentOffset(.zero, animated: animated)
    }

    /// Enables moderator actions once the logged-in user is seen wearing a
    /// moderator/broadcaster badge in this channel — avoids showing mod controls
    /// to regular viewers without needing an extra API scope.
    private func detectModeratorIfNeeded(_ rows: [ChatRow]) {
        guard !canModerate, !isAnonymous, !isReadOnly, let me = currentUserLogin?.lowercased() else { return }
        let isMod = rows.contains { row in
            row.message.author.login.lowercased() == me
                && row.message.badges.contains { $0.setID == "moderator" || $0.setID == "broadcaster" }
        }
        if isMod { canModerate = true }
    }

    private func jumpToLatest() {
        searchField.isHidden = true
        searchField.text = nil
        searchField.resignFirstResponder()
        viewModel.setPaused(false)
        scrollToLatest(animated: true)
    }

    @objc private func searchChanged() {
        viewModel.search(searchField.text ?? "")
    }

    @objc private func dismissKeyboardOnTap() {
        view.endEditing(true)
    }

    @objc private func handleMessageLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        let point = recognizer.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point),
              let row = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.impact(.medium)
        let sourceRect = collectionView.layoutAttributesForItem(at: indexPath)
            .map { collectionView.convert($0.frame, to: view) }
            ?? CGRect(origin: view.convert(point, from: collectionView), size: .zero)
        presentMessageActions(for: row.message, sourceRect: sourceRect)
    }

}

extension ChatViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

extension ChatViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width
        guard let row = dataSource.itemIdentifier(for: indexPath), let laidOut = row.laidOut else {
            return CGSize(width: width, height: 1)
        }
        return CGSize(width: width, height: laidOut.height)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let delta = abs(scrollView.contentOffset.y - lastContentOffsetY)
        lastContentOffsetY = scrollView.contentOffset.y
        let wasFast = fastScroll
        fastScroll = delta > 40
        if fastScroll != wasFast {
            animator.isPaused = fastScroll
        }

        let atBottom = scrollView.contentOffset.y <= 8
        if atBottom {
            if isPaused {
                isPaused = false
                searchField.isHidden = true
                viewModel.setPaused(false)
            }
        } else if !isPaused {
            isPaused = true
            viewModel.setPaused(true)
            searchField.isHidden = false
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        fastScroll = false
        animator.isPaused = false
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
    }

    private func presentMessageActions(for message: ChatMessage, sourceRect: CGRect) {
        let isOwn = message.author.login.lowercased() == currentUserLogin?.lowercased()
        let sheet = UIAlertController(title: message.author.displayName, message: nil, preferredStyle: .actionSheet)
        if !isAnonymous && !isReadOnly {
            sheet.addAction(UIAlertAction(title: String(localized: "Reply"), style: .default) { [weak self] _ in
                guard let self else { return }
                self.delegate?.chatViewController(self, didRequestReplyTo: message)
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "View Profile"), style: .default) { [weak self] _ in
            self?.presentUserCard(for: message.author, message: message)
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Copy Message"), style: .default) { _ in
            UIPasteboard.general.string = message.plainText
        })
        if canModerate, !isOwn {
            sheet.addAction(UIAlertAction(title: String(localized: "Delete Message"), style: .destructive) { [weak self] _ in
                self?.viewModel.deleteMessage(messageID: message.id)
            })
            sheet.addAction(UIAlertAction(title: String(localized: "Timeout 10 min"), style: .default) { [weak self] _ in
                self?.viewModel.timeoutUser(userID: message.author.id, duration: 600)
            })
            sheet.addAction(UIAlertAction(title: String(localized: "Ban"), style: .destructive) { [weak self] _ in
                self?.viewModel.banUser(userID: message.author.id)
            })
        }
        if !isOwn {
            sheet.addAction(UIAlertAction(title: String(localized: "Block @\(message.author.login)"), style: .destructive) { [weak self] _ in
                guard let self else { return }
                Haptics.notify(.success)
                self.viewModel.block(
                    userID: message.author.id,
                    login: message.author.login,
                    message: message,
                    channelLogin: self.broadcasterLogin
                )
            })
        }
        if !isOwn {
            sheet.addAction(UIAlertAction(title: String(localized: "Report Message"), style: .destructive) { [weak self] _ in
                self?.presentReportReasons(for: message, sourceRect: sourceRect)
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = sourceRect
        }
        present(sheet, animated: true)
    }

    private func presentReportReasons(for message: ChatMessage, sourceRect: CGRect) {
        let sheet = UIAlertController(
            title: String(localized: "Report @\(message.author.login)"),
            message: String(localized: "Reports are reviewed and this user will be hidden from your chat."),
            preferredStyle: .actionSheet
        )
        for reason in ChatReportReason.allCases {
            sheet.addAction(UIAlertAction(title: reason.title, style: .destructive) { [weak self] _ in
                guard let self else { return }
                Haptics.notify(.success)
                self.viewModel.report(message: message, reason: reason.rawValue, channelLogin: self.broadcasterLogin)
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = sourceRect
        }
        present(sheet, animated: true)
    }
}

extension ChatViewController: ChatInputViewDelegate {
    func chatInput(_ input: ChatInputView, didSubmit text: String) {
        if text.trimmingCharacters(in: .whitespaces).hasPrefix("/") {
            input.setSending(true)
            Task { [weak self] in
                guard let self else { return }
                let outcome = await self.viewModel.runCommand(text.trimmingCharacters(in: .whitespaces))
                input.setSending(false)
                if case .handled = outcome {
                    Haptics.selection()
                    input.clear()
                    input.hideReply()
                } else {
                    self.performSend(text, input: input)
                }
            }
            return
        }
        performSend(text, input: input)
    }

    private func performSend(_ text: String, input: ChatInputView) {
        input.setSending(true)
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.viewModel.send(text)
                input.setSending(false)
                if result.isSent {
                    Haptics.notify(.success)
                    input.clear()
                    input.hideReply()
                } else {
                    Haptics.notify(.error)
                    input.showDropReason(result.dropReason ?? String(localized: "Message rejected"))
                }
            } catch {
                Haptics.notify(.error)
                input.setSending(false)
                input.showDropReason(Self.describe(error))
                MidgarLog.notice("Chat send failed: \(error)", category: .chat)
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let apiError = error as? APIError else { return String(localized: "Failed to send") }
        switch apiError {
        case .unauthorized: return String(localized: "Sign in to chat")
        case .forbidden: return String(localized: "You can't send messages here")
        case .rateLimited: return String(localized: "Slow down — you're sending too fast")
        case .invalidRequest(let reason): return reason
        case .network: return String(localized: "Network error")
        case .timeout: return String(localized: "Timed out")
        default: return String(localized: "Failed to send")
        }
    }

    func chatInput(_ input: ChatInputView, suggestionsFor token: AutocompleteToken) -> [AutocompleteSuggestion] {
        switch token {
        case .emote(let query):
            return emoteSuggestions(matching: query)
        case .mention(let query):
            return mentionSuggestions(matching: query)
        }
    }

    func chatInputDidCancelReply(_ input: ChatInputView) {
        viewModel.setReply(parentID: nil)
        input.hideReply()
    }

    func beginReply(to message: ChatMessage) {
        guard !isAnonymous else { return }
        Haptics.impact(.light)
        viewModel.setReply(parentID: message.id)
        composer.showReply(displayName: message.author.displayName, text: message.plainText)
        DispatchQueue.main.async { [weak self] in
            _ = self?.composer.becomeFirstResponder()
        }
    }

    private func emoteSuggestions(matching query: String) -> [AutocompleteSuggestion] {
        let lowered = query.lowercased()
        let pool = Array(catalog.channel.values) + Array(catalog.global.values)
        let matches = pool.filter { $0.name.lowercased().contains(lowered) }
            .sorted { lhs, rhs in
                let lp = lhs.name.lowercased().hasPrefix(lowered)
                let rp = rhs.name.lowercased().hasPrefix(lowered)
                if lp != rp { return lp }
                return lhs.name.count < rhs.name.count
            }
            .prefix(20)
        return matches.map { .emote($0) }
    }

    private func mentionSuggestions(matching query: String) -> [AutocompleteSuggestion] {
        let lowered = query.lowercased()
        return chatterIndex
            .filter { $0.key.contains(lowered) }
            .sorted { $0.key < $1.key }
            .prefix(20)
            .map { .mention(login: $0.key, displayName: $0.value) }
    }
}
