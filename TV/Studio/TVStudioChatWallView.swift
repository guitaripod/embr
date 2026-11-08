import UIKit
import Combine
import EmbrCore

/// Studio's chat on the TV: Embr's chat engine at a size read from across the room. Moving focus into it walks the
/// messages from the newest up, with new ones held back so nothing shifts under the focus; a pill counts them, and
/// leaving the chat or pressing Back catches up. Play/Pause freezes it the same way.
final class TVStudioChatWallView: UIView, UICollectionViewDelegateFlowLayout {
    var onSelect: ((ChatMessage) -> Void)?
    var onHistoryChange: ((Bool) -> Void)?

    private let viewModel: ChatViewModel
    private let scale: StudioScale
    private let header = UILabel()
    private let modesLabel = UILabel()
    private let pausedChip = UILabel()
    private let pill = UILabel()
    private let collectionView: UICollectionView
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private var rows: [String: ChatRow] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let animator = EmoteAnimator()
    private var lastWidth: CGFloat = 0
    private(set) var isFrozen = false
    private var frozenByRemote = false
    private var sharedChat: [String] = []
    private var roomState: RoomState?

    private static let visibleRows = 150

    init(viewModel: ChatViewModel, scale: StudioScale) {
        self.viewModel = viewModel
        self.scale = scale
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 2
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        build()
        configureDataSource()
        bind()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func start() {
        animator.isPaused = !SettingsStore.shared.current.animateEmotes
    }

    func stop() {
        animator.isPaused = true
    }

    /// Freezes or thaws chat from Play/Pause.
    func toggleFreeze() {
        frozenByRemote.toggle()
        setFrozen(frozenByRemote)
    }

    /// Lets chat run again, as Back does from history.
    func catchUp() {
        frozenByRemote = false
        setFrozen(false)
    }

    func showShared(_ shared: StudioSharedChat?) {
        sharedChat = shared?.participants ?? []
        refreshHeader()
    }

    func relayout() {
        lastWidth = 0
        setNeedsLayout()
    }

    var newestCell: UIView? {
        guard let id = dataSource.snapshot().itemIdentifiers.first, let path = dataSource.indexPath(for: id) else { return nil }
        return collectionView.cellForItem(at: path)
    }

    var focusTarget: UIView { collectionView }

    private func setFrozen(_ frozen: Bool) {
        guard frozen != isFrozen else { return }
        isFrozen = frozen
        viewModel.setPaused(frozen)
        pausedChip.isHidden = !(frozen && frozenByRemote)
        onHistoryChange?(frozen)
        if !frozen { pill.isHidden = true }
    }

    private func build() {
        backgroundColor = StudioPalette.panel
        layer.cornerRadius = scale.corner
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = StudioPalette.line.cgColor
        clipsToBounds = true

        header.text = String(localized: "Chat", comment: "Studio chat header")
        header.font = scale.font(scale.caption, .bold, style: .caption1)
        header.textColor = StudioPalette.text
        modesLabel.font = scale.font(scale.caption, style: .caption1)
        modesLabel.textColor = StudioPalette.muted
        pausedChip.text = "  " + String(localized: "Paused", comment: "Studio chat frozen by Play/Pause") + "  "
        pausedChip.font = scale.font(scale.caption, .bold, style: .caption1)
        pausedChip.textColor = UIColor(red: 1, green: 0.83, blue: 0.42, alpha: 1)
        pausedChip.layer.borderColor = pausedChip.textColor.cgColor
        pausedChip.layer.borderWidth = 2
        pausedChip.layer.cornerRadius = scale.caption * 0.8
        pausedChip.isHidden = true
        let headerRow = UIStackView(arrangedSubviews: [header, modesLabel, UIView(), pausedChip])
        headerRow.spacing = scale.spacing
        headerRow.alignment = .center
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerRow)

        collectionView.backgroundColor = .clear
        collectionView.transform = CGAffineTransform(scaleX: 1, y: -1)
        collectionView.showsVerticalScrollIndicator = false
        collectionView.delegate = self
        collectionView.remembersLastFocusedIndexPath = false
        collectionView.register(MessageCell.self, forCellWithReuseIdentifier: MessageCell.reuseID)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)

        pill.font = scale.font(scale.caption * 1.1, .bold, style: .callout)
        pill.textColor = UIColor(white: 0.07, alpha: 1)
        pill.backgroundColor = StudioPalette.text
        pill.textAlignment = .center
        pill.layer.cornerRadius = scale.caption * 1.1
        pill.clipsToBounds = true
        pill.isHidden = true
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)

        NSLayoutConstraint.activate([
            headerRow.topAnchor.constraint(equalTo: topAnchor, constant: scale.padding * 0.7),
            headerRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: scale.padding),
            headerRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -scale.padding),
            collectionView.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: scale.spacing * 0.5),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: scale.padding * 0.4),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -scale.padding * 0.4),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -scale.padding * 0.4),
            pill.centerXAnchor.constraint(equalTo: centerXAnchor),
            pill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -scale.padding),
            pill.heightAnchor.constraint(equalToConstant: scale.caption * 2.2),
            pill.widthAnchor.constraint(greaterThanOrEqualToConstant: scale.caption * 14),
        ])
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, id in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MessageCell.reuseID, for: indexPath)
            guard let self, let messageCell = cell as? MessageCell, let row = self.rows[id], let laidOut = row.laidOut else { return cell }
            messageCell.configure(with: laidOut, message: row.message, images: AppContainer.shared.images, animator: self.animator)
            messageCell.layer.cornerRadius = self.scale.corner * 0.5
            return messageCell
        }
    }

    private func bind() {
        viewModel.snapshotSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in self?.render(snapshot) }
            .store(in: &cancellables)
        viewModel.roomStateSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.roomState = state
                self?.refreshHeader()
            }
            .store(in: &cancellables)
    }

    var currentRoomState: RoomState? { roomState }

    private func refreshHeader() {
        var parts: [String] = []
        if let state = roomState {
            if state.emoteOnly { parts.append(String(localized: "Emote-only")) }
            if state.subscribersOnly { parts.append(String(localized: "Subscribers-only")) }
            if let followers = state.followersOnly, followers >= 0 { parts.append(String(localized: "Followers-only")) }
            if let slow = state.slowMode, slow > 0 { parts.append(String(localized: "Slow \(slow) s", comment: "Studio chat header, slow mode seconds")) }
        }
        if !sharedChat.isEmpty {
            parts.append(String(localized: "Shared with \(sharedChat.joined(separator: ", "))", comment: "Studio chat header, shared chat session"))
        }
        modesLabel.text = parts.joined(separator: "  ·  ")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = collectionView.bounds.width
        guard width > 0, width != lastWidth else { return }
        lastWidth = width
        viewModel.updateWidth(width)
    }

    private func render(_ snapshot: ChatSnapshot) {
        if snapshot.isPaused, snapshot.newCount > 0 {
            pill.isHidden = false
            pill.text = String(localized: "\(snapshot.newCount) new messages · Back for live", comment: "Studio chat, messages waiting while frozen")
        } else if !snapshot.isPaused {
            pill.isHidden = true
        }
        if snapshot.isPaused, !snapshot.relayout, !rows.isEmpty, dataSource.snapshot().numberOfItems > 0 {
            let current = Set(dataSource.snapshot().itemIdentifiers)
            let changed = snapshot.rows.filter { current.contains($0.id) && rows[$0.id] != $0 }
            guard !changed.isEmpty else { return }
            for row in changed { rows[row.id] = row }
            var diffable = dataSource.snapshot()
            diffable.reconfigureItems(changed.map(\.id))
            dataSource.apply(diffable, animatingDifferences: false)
            return
        }
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

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let id = dataSource.itemIdentifier(for: indexPath), let laidOut = rows[id]?.laidOut else {
            return CGSize(width: collectionView.bounds.width, height: 1)
        }
        return CGSize(width: collectionView.bounds.width, height: laidOut.height)
    }

    func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
        true
    }

    func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        let entering = context.nextFocusedIndexPath != nil
        if entering, !isFrozen { setFrozen(true) }
        if !entering, isFrozen, !frozenByRemote { setFrozen(false) }
        coordinator.addCoordinatedAnimations {
            if let previous = context.previouslyFocusedView {
                previous.backgroundColor = .clear
                previous.transform = .identity
                previous.layer.shadowOpacity = 0
            }
            if let next = context.nextFocusedView as? MessageCell {
                next.backgroundColor = UIColor.white.withAlphaComponent(0.16)
                next.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
                next.layer.shadowColor = UIColor.black.cgColor
                next.layer.shadowOpacity = 0.5
                next.layer.shadowRadius = 18
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let id = dataSource.itemIdentifier(for: indexPath), let row = rows[id], row.message.notice == nil else { return }
        onSelect?(row.message)
    }

    func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
        dataSource.snapshot().numberOfItems > 0 ? IndexPath(item: 0, section: 0) : nil
    }
}
