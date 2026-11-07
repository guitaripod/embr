import UIKit
import Combine
import EmbrCore

/// Live or replayed chat beside the video: the same chat engine and message rendering as the iPhone, laid out for
/// reading from the couch. It takes no focus, so the remote keeps driving the player.
final class TVChatPanelView: UIView, UICollectionViewDelegateFlowLayout {
    static let width: CGFloat = 520

    private let viewModel: ChatViewModel
    private let backdrop = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let tint = UIView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let collectionView: UICollectionView
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private var rows: [String: ChatRow] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let animator = EmoteAnimator()
    private var lastWidth: CGFloat = 0

    /// The newest messages kept on screen; older ones scroll away for good, as there is no scrolling back on a TV.
    private static let visibleRows = 120

    init(viewModel: ChatViewModel, title: String) {
        self.viewModel = viewModel
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        overrideUserInterfaceStyle = .dark
        buildHierarchy(title: title)
        configureDataSource()
        bind()
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeFocused: Bool { false }

    private func buildHierarchy(title: String) {
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        tint.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        tint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tint)

        titleLabel.text = title
        titleLabel.font = TVFont.bold(.callout)
        titleLabel.textColor = .white
        statusLabel.font = TVFont.cardSubtitle
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        let header = UIStackView(arrangedSubviews: [titleLabel, statusLabel])
        header.axis = .vertical
        header.spacing = 2
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        collectionView.backgroundColor = .clear
        collectionView.transform = CGAffineTransform(scaleX: 1, y: -1)
        collectionView.isScrollEnabled = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.delegate = self
        collectionView.register(MessageCell.self, forCellWithReuseIdentifier: MessageCell.reuseID)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)

        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            tint.topAnchor.constraint(equalTo: topAnchor),
            tint.leadingAnchor.constraint(equalTo: leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: trailingAnchor),
            tint.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 48),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            collectionView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -40),
        ])
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, id in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MessageCell.reuseID, for: indexPath)
            guard let self, let messageCell = cell as? MessageCell, let row = self.rows[id], let laidOut = row.laidOut else { return cell }
            messageCell.configure(with: laidOut, message: row.message, images: AppContainer.shared.images, animator: self.animator)
            return messageCell
        }
    }

    private func bind() {
        viewModel.snapshotSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.render(snapshot) }
            .store(in: &cancellables)
        viewModel.connectionSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.show(status) }
            .store(in: &cancellables)
        viewModel.roomStateSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.show(state) }
            .store(in: &cancellables)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = collectionView.bounds.width
        guard width > 0, width != lastWidth else { return }
        lastWidth = width
        viewModel.updateWidth(width)
    }

    func start() {
        viewModel.start()
        animator.isPaused = !SettingsStore.shared.current.animateEmotes
    }

    func stop() {
        viewModel.stop()
        animator.isPaused = true
    }

    /// Moves chat replay to the past broadcast's playback position.
    func setPlayback(seconds: TimeInterval) {
        viewModel.setPlayback(seconds: seconds)
    }

    /// Lays the messages out again at the current text size, after the chat menu changed it.
    func relayout() {
        lastWidth = 0
        setNeedsLayout()
    }

    private func render(_ snapshot: ChatSnapshot) {
        let shown = snapshot.rows.suffix(Self.visibleRows).filter { $0.laidOut != nil }.reversed()
        rows = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var diffable = NSDiffableDataSourceSnapshot<Int, String>()
        diffable.appendSections([0])
        diffable.appendItems(shown.map(\.id))
        if snapshot.relayout {
            diffable.reloadItems(diffable.itemIdentifiers)
        } else {
            let current = Set(dataSource.snapshot().itemIdentifiers)
            diffable.reconfigureItems(diffable.itemIdentifiers.filter { current.contains($0) })
        }
        dataSource.apply(diffable, animatingDifferences: !UIAccessibility.isReduceMotionEnabled && !snapshot.relayout)
    }

    private func show(_ status: ConnectionStatus) {
        switch status {
        case .connected: statusLabel.text = String(localized: "Live chat", comment: "Chat panel status while connected")
        case .connecting, .idle: statusLabel.text = String(localized: "Connecting to chat…")
        case .reconnecting: statusLabel.text = String(localized: "Reconnecting…")
        case .disconnected: statusLabel.text = String(localized: "Chat disconnected")
        }
    }

    private func show(_ state: RoomState) {
        var modes: [String] = []
        if state.emoteOnly { modes.append(String(localized: "Emote-only")) }
        if state.subscribersOnly { modes.append(String(localized: "Subscribers-only")) }
        if let followers = state.followersOnly, followers >= 0 { modes.append(String(localized: "Followers-only")) }
        if let slow = state.slowMode, slow > 0 { modes.append(String(localized: "Slow mode")) }
        guard !modes.isEmpty else { return }
        statusLabel.text = modes.joined(separator: " · ")
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let id = dataSource.itemIdentifier(for: indexPath), let laidOut = rows[id]?.laidOut else {
            return CGSize(width: collectionView.bounds.width, height: 1)
        }
        return CGSize(width: collectionView.bounds.width, height: laidOut.height)
    }

    func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
        false
    }
}
