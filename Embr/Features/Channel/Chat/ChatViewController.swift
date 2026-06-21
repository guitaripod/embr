import UIKit
import Combine
import EmbrCore

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
    private let animator = EmoteAnimator.shared

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, ChatRow>!
    private lazy var composer = ChatInputView(images: images)
    private lazy var guestBar = GuestChatBar()
    private let statusBar = ConnectionStatusBar()
    private let newMessagesPill = NewMessagesPill()
    private let searchField = UISearchTextField()
    private let emptyLabel = UILabel()

    private var cancellables = Set<AnyCancellable>()
    private var isPaused = false
    private var pausedForMenu = false
    private var lastContentOffsetY: CGFloat = 0
    private var fastScroll = false

    private var inputBottomConstraint: NSLayoutConstraint?
    private var catalog = EmoteCatalog()
    private var chatterIndex: [String: String] = [:]
    private var lastLayoutWidth: CGFloat = 0

    init(viewModel: ChatViewModel, images: ImageLoading = AppContainer.shared.images, isAnonymous: Bool) {
        self.viewModel = viewModel
        self.images = images
        self.isAnonymous = isAnonymous
        super.init(nibName: nil, bundle: nil)
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
        setUpKeyboardObservers()
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
        let width = collectionView.bounds.width
        guard width > 0, width != lastLayoutWidth else { return }
        lastLayoutWidth = width
        viewModel.updateWidth(width)
        collectionView.collectionViewLayout.invalidateLayout()
    }

    func endSession() {
        viewModel.stop()
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
        collectionView.contentInsetAdjustmentBehavior = .never
        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboardOnTap))
        dismissTap.cancelsTouchesInView = false
        dismissTap.delegate = self
        collectionView.addGestureRecognizer(dismissTap)
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
                guard let self else { return }
                self.delegate?.chatViewController(self, didTapUsername: user)
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
        }
        dataSource = UICollectionViewDiffableDataSource<Int, ChatRow>(collectionView: collectionView) { collectionView, indexPath, row in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: row)
        }
    }

    private func setUpOverlays() {
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "Waiting for messages…"
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
        searchField.placeholder = "Search chat"
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
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            newMessagesPill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            newMessagesPill.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor, constant: -12)
        ])

        view.bringSubviewToFront(statusBar)
    }

    private func setUpInput() {
        guard !isAnonymous else {
            setUpGuestBar()
            return
        }
        composer.translatesAutoresizingMaskIntoConstraints = false
        composer.delegate = self
        view.addSubview(composer)

        let bottom = composer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        inputBottomConstraint = bottom

        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom,
            collectionView.bottomAnchor.constraint(equalTo: composer.topAnchor)
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

    private func setUpKeyboardObservers() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                MainActor.assumeIsolated { self?.handleKeyboard(note) }
            }
            .store(in: &cancellables)
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
    }

    private func apply(_ snapshot: ChatSnapshot) {
        isPaused = snapshot.isPaused
        emptyLabel.isHidden = !snapshot.rows.isEmpty
        for row in snapshot.rows {
            chatterIndex[row.message.author.login.lowercased()] = row.message.author.displayName
        }

        var diff = NSDiffableDataSourceSnapshot<Int, ChatRow>()
        diff.appendSections([0])
        diff.appendItems(snapshot.rows.reversed(), toSection: 0)
        let shouldStickToBottom = !snapshot.isPaused
        dataSource.apply(diff, animatingDifferences: false) { [weak self] in
            guard let self, shouldStickToBottom else { return }
            self.scrollToLatest(animated: false)
        }

        if snapshot.isPaused, snapshot.newCount > 0 {
            newMessagesPill.setCount(snapshot.newCount)
            newMessagesPill.isHidden = false
        } else {
            newMessagesPill.isHidden = true
        }
    }

    private func scrollToLatest(animated: Bool) {
        guard collectionView.numberOfSections > 0, collectionView.numberOfItems(inSection: 0) > 0 else { return }
        collectionView.setContentOffset(.zero, animated: animated)
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

    private func handleKeyboard(_ note: Notification) {
        guard let frameValue = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
              let durationValue = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber else { return }
        let endFrame = view.convert(frameValue.cgRectValue, from: nil)
        let overlap = max(0, view.bounds.maxY - endFrame.minY)
        inputBottomConstraint?.constant = -overlap
        UIView.animate(withDuration: durationValue.doubleValue) { self.view.layoutIfNeeded() }
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

    func collectionView(_ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration, highlightPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? {
        makePreview(for: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration, dismissalPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? {
        makePreview(for: indexPath)
    }

    private func makePreview(for indexPath: IndexPath) -> UITargetedPreview? {
        guard let cell = collectionView.cellForItem(at: indexPath) as? MessageCell else { return nil }
        let center = collectionView.convert(cell.center, to: view)
        return cell.makeUprightContextPreview(in: view, center: center)
    }

    func collectionView(_ collectionView: UICollectionView, willDisplayContextMenu configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        guard !isPaused else { return }
        pausedForMenu = true
        isPaused = true
        viewModel.setPaused(true)
    }

    func collectionView(_ collectionView: UICollectionView, willEndContextMenuInteraction configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        guard pausedForMenu else { return }
        pausedForMenu = false
        guard collectionView.contentOffset.y <= 8 else { return }
        isPaused = false
        viewModel.setPaused(false)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            var actions: [UIAction] = []
            if !self.isAnonymous {
                actions.append(UIAction(title: "Reply", image: UIImage(systemName: "arrowshape.turn.up.left")) { [weak self] _ in
                    guard let self else { return }
                    self.delegate?.chatViewController(self, didRequestReplyTo: row.message)
                })
            }
            actions.append(UIAction(title: "Copy Message", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = row.message.plainText
            })
            actions.append(UIAction(title: "Copy @\(row.message.author.login)", image: UIImage(systemName: "person")) { _ in
                UIPasteboard.general.string = "@\(row.message.author.login)"
            })
            return UIMenu(children: actions)
        }
    }
}

extension ChatViewController: ChatInputViewDelegate {
    func chatInput(_ input: ChatInputView, didSubmit text: String) {
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
                    input.showDropReason(result.dropReason ?? "Message rejected")
                }
            } catch {
                Haptics.notify(.error)
                input.setSending(false)
                input.showDropReason(Self.describe(error))
                AppLogger.shared.warn("Chat send failed: \(error)", category: .chat)
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let apiError = error as? APIError else { return "Failed to send" }
        switch apiError {
        case .unauthorized: return "Sign in to chat"
        case .forbidden: return "You can't send messages here"
        case .rateLimited: return "Slow down — you're sending too fast"
        case .invalidRequest(let reason): return reason
        case .network: return "Network error"
        case .timeout: return "Timed out"
        default: return "Failed to send"
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
        composer.becomeFirstResponder()
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

@MainActor
private final class ConnectionStatusBar: UIView {
    var onTapReconnect: (() -> Void)?

    private let icon = UIImageView()
    private let label = UILabel()
    private let roomStateLabel = UILabel()
    private let statusRow = UIStackView()
    private var noticeDismiss: DispatchWorkItem?
    private var lastStatus: ConnectionStatus = .idle
    private var canReconnect = false

    init() {
        super.init(frame: .zero)
        setUp()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleTap() {
        guard canReconnect else { return }
        onTapReconnect?()
    }

    func showNotice(_ notice: SystemNotice) {
        show(
            text: notice.text,
            symbol: notice.isError ? "exclamationmark.triangle.fill" : "info.circle",
            pulse: false,
            color: notice.isError ? .systemRed : Theme.secondaryText
        )
        noticeDismiss?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.noticeDismiss = nil
            self.applyStatus(self.lastStatus)
        }
        noticeDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    func update(_ status: ConnectionStatus) {
        lastStatus = status
        noticeDismiss?.cancel()
        noticeDismiss = nil
        applyStatus(status)
    }

    private func applyStatus(_ status: ConnectionStatus) {
        canReconnect = false
        switch status {
        case .idle, .connected:
            statusRow.isHidden = true
            icon.removeAllSymbolEffects()
            updateContainerVisibility()
        case .connecting:
            show(text: "Connecting…", symbol: "dot.radiowaves.left.and.right", pulse: true, color: Theme.slowMode)
        case .reconnecting(let attempt):
            show(text: "Reconnecting (\(attempt))…", symbol: "arrow.triangle.2.circlepath", pulse: true, color: Theme.slowMode)
        case .disconnected(let reason):
            canReconnect = true
            show(text: reason ?? "Disconnected · Tap to reconnect", symbol: "arrow.clockwise", pulse: false, color: .systemRed)
        }
    }

    func update(roomState: RoomState) {
        var parts: [String] = []
        if roomState.emoteOnly { parts.append("Emote-only") }
        if roomState.subscribersOnly { parts.append("Subs-only") }
        if let seconds = roomState.followersOnly { parts.append(seconds == 0 ? "Followers-only" : "Followers \(seconds)m") }
        if let slow = roomState.slowMode { parts.append("Slow \(slow)s") }
        if roomState.uniqueChat { parts.append("Unique") }
        roomStateLabel.text = parts.joined(separator: " · ")
        roomStateLabel.isHidden = parts.isEmpty
        updateContainerVisibility()
    }

    private func show(text: String, symbol: String, pulse: Bool, color: UIColor) {
        statusRow.isHidden = false
        label.text = text
        label.textColor = color
        icon.image = UIImage(systemName: symbol)
        icon.tintColor = color
        icon.removeAllSymbolEffects()
        if pulse { icon.addSymbolEffect(.pulse, options: .repeating) }
        updateContainerVisibility()
    }

    private func updateContainerVisibility() {
        isHidden = statusRow.isHidden && roomStateLabel.isHidden
    }

    private func setUp() {
        if Glass.isAvailable {
            backgroundColor = .clear
            let glass = Glass.view()
            addSubview(glass)
            NSLayoutConstraint.activate([
                glass.topAnchor.constraint(equalTo: topAnchor),
                glass.bottomAnchor.constraint(equalTo: bottomAnchor),
                glass.leadingAnchor.constraint(equalTo: leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        } else {
            backgroundColor = Theme.surface.withAlphaComponent(0.95)
        }
        icon.contentMode = .scaleAspectFit
        label.font = .systemFont(ofSize: 13, weight: .medium)
        roomStateLabel.font = .systemFont(ofSize: 11, weight: .regular)
        roomStateLabel.textColor = Theme.secondaryText
        roomStateLabel.isHidden = true

        statusRow.addArrangedSubview(icon)
        statusRow.addArrangedSubview(label)
        statusRow.axis = .horizontal
        statusRow.spacing = 6
        statusRow.alignment = .center
        statusRow.isHidden = true

        let stack = UIStackView(arrangedSubviews: [statusRow, roomStateLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16)
        ])
    }
}

@MainActor
private final class NewMessagesPill: UIControl {
    var onTap: (() -> Void)?
    private let label = UILabel()
    private let icon = UIImageView()

    init() {
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setCount(_ count: Int) {
        label.text = count == 1 ? "1 new message" : "\(count) new messages"
    }

    private func setUp() {
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        addTarget(self, action: #selector(tapped), for: .touchUpInside)

        if Glass.isAvailable {
            backgroundColor = .clear
            let glass = Glass.view(cornerRadius: 16, tint: Theme.accent, interactive: true)
            glass.isUserInteractionEnabled = false
            addSubview(glass)
            NSLayoutConstraint.activate([
                glass.topAnchor.constraint(equalTo: topAnchor),
                glass.bottomAnchor.constraint(equalTo: bottomAnchor),
                glass.leadingAnchor.constraint(equalTo: leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        } else {
            backgroundColor = Theme.accent
        }

        icon.image = UIImage(systemName: "arrow.down")
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit

        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white

        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 16)
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    @objc private func tapped() {
        onTap?()
    }
}

@MainActor
private final class GuestChatBar: UIView {
    var onLogin: (() -> Void)?
    private let loginButton = UIButton(type: .system)

    init() {
        super.init(frame: .zero)
        backgroundColor = Theme.surface

        let icon = UIImageView(image: UIImage(systemName: "bubble.left.and.bubble.right"))
        icon.tintColor = Theme.secondaryText
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = "Log in to chat"
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = Theme.secondaryText

        var configuration = UIButton.Configuration.tinted()
        configuration.title = "Log In"
        configuration.cornerStyle = .large
        configuration.baseForegroundColor = Theme.accent
        loginButton.configuration = configuration
        loginButton.setContentHuggingPriority(.required, for: .horizontal)
        loginButton.addAction(UIAction { [weak self] _ in self?.onLogin?() }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [icon, label, loginButton])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 12)
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
