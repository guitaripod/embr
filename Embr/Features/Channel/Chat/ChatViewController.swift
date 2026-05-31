import UIKit
import Combine
import EmbrCore

@MainActor
protocol ChatViewControllerDelegate: AnyObject {
    func chatViewController(_ controller: ChatViewController, didTapUsername user: ChatUser)
    func chatViewController(_ controller: ChatViewController, didTapEmote emote: Emote)
    func chatViewController(_ controller: ChatViewController, didTapLink url: URL)
    func chatViewController(_ controller: ChatViewController, didRequestReplyTo message: ChatMessage)
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
    private lazy var inputView = ChatInputView(images: images)
    private let statusBar = ConnectionStatusBar()
    private let newMessagesPill = NewMessagesPill()
    private let searchField = UISearchTextField()

    private var cancellables = Set<AnyCancellable>()
    private var isPaused = false
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
        bind()
        viewModel.start()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = collectionView.bounds.width
        guard width > 0, width != lastLayoutWidth else { return }
        lastLayoutWidth = width
        viewModel.updateWidth(width)
        collectionView.collectionViewLayout.invalidateLayout()
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
        }
        dataSource = UICollectionViewDiffableDataSource<Int, ChatRow>(collectionView: collectionView) { collectionView, indexPath, row in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: row)
        }
    }

    private func setUpOverlays() {
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
    }

    private func setUpInput() {
        inputView.translatesAutoresizingMaskIntoConstraints = false
        inputView.delegate = self
        inputView.isHidden = isAnonymous
        view.addSubview(inputView)

        let bottom = inputView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        inputBottomConstraint = bottom

        let collectionBottom = isAnonymous
            ? collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            : collectionView.bottomAnchor.constraint(equalTo: inputView.topAnchor)

        NSLayoutConstraint.activate([
            inputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom,
            collectionBottom
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
                MainActor.assumeIsolated { self?.statusBar.update(roomState: state) }
            }
            .store(in: &cancellables)

        viewModel.catalogSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] catalog in
                MainActor.assumeIsolated {
                    self?.catalog = catalog
                    self?.inputView.setCatalog(catalog)
                }
            }
            .store(in: &cancellables)
    }

    private func apply(_ snapshot: ChatSnapshot) {
        isPaused = snapshot.isPaused
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

    private func handleKeyboard(_ note: Notification) {
        guard let frameValue = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
              let durationValue = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber else { return }
        let endFrame = frameValue.cgRectValue
        let overlap = max(0, view.bounds.height - view.safeAreaInsets.bottom - endFrame.minY)
        inputBottomConstraint?.constant = -overlap
        UIView.animate(withDuration: durationValue.doubleValue) { self.view.layoutIfNeeded() }
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
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }
        delegate?.chatViewController(self, didRequestReplyTo: row.message)
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
                    input.clear()
                    input.hideReply()
                } else {
                    input.showDropReason(result.dropReason ?? "Message rejected")
                }
            } catch {
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
        viewModel.setReply(parentID: message.id)
        inputView.showReply(displayName: message.author.displayName, text: message.plainText)
        inputView.becomeFirstResponder()
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
    private let icon = UIImageView()
    private let label = UILabel()
    private let roomStateLabel = UILabel()

    init() {
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(_ status: ConnectionStatus) {
        switch status {
        case .idle, .connected:
            isHidden = true
            icon.removeAllSymbolEffects()
        case .connecting:
            show(text: "Connecting…", symbol: "dot.radiowaves.left.and.right", pulse: true, color: Theme.slowMode)
        case .reconnecting(let attempt):
            show(text: "Reconnecting (\(attempt))…", symbol: "arrow.triangle.2.circlepath", pulse: true, color: Theme.slowMode)
        case .disconnected(let reason):
            show(text: reason ?? "Disconnected", symbol: "exclamationmark.triangle.fill", pulse: false, color: .systemRed)
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
    }

    private func show(text: String, symbol: String, pulse: Bool, color: UIColor) {
        isHidden = false
        label.text = text
        label.textColor = color
        icon.image = UIImage(systemName: symbol)
        icon.tintColor = color
        icon.removeAllSymbolEffects()
        if pulse { icon.addSymbolEffect(.pulse, options: .repeating) }
    }

    private func setUp() {
        backgroundColor = Theme.surface.withAlphaComponent(0.95)
        icon.contentMode = .scaleAspectFit
        label.font = .systemFont(ofSize: 13, weight: .medium)
        roomStateLabel.font = .systemFont(ofSize: 11, weight: .regular)
        roomStateLabel.textColor = Theme.secondaryText
        roomStateLabel.isHidden = true

        let statusRow = UIStackView(arrangedSubviews: [icon, label])
        statusRow.axis = .horizontal
        statusRow.spacing = 6
        statusRow.alignment = .center

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
        backgroundColor = Theme.accent
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        addTarget(self, action: #selector(tapped), for: .touchUpInside)

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
