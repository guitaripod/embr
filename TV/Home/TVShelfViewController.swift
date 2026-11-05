import UIKit
import EmbrCore
import MidgarCore

/// A screen of horizontal shelves or a grid: the Following, Favorites and Browse tabs, a category, search results.
/// Subclasses load their shelves and call ``apply(_:)``; this class lays them out, keeps focus on the same card across
/// refreshes, starts the live preview on a focused stream, routes a click and offers the long-press menu.
class TVShelfViewController: UIViewController, UICollectionViewDelegate {
    private(set) var collectionView: UICollectionView!
    let stateView = TVStateView()
    private var dataSource: UICollectionViewDiffableDataSource<String, String>!
    private var shelves: [TVShelf] = []
    private var items: [String: TVShelfItem] = [:]
    private var refreshTimer: Timer?
    private var lastLoad: Date?
    private var foregroundObserver: (any NSObjectProtocol)?

    /// How often a visible screen reloads its shelves; live streams come and go and viewer counts move.
    var refreshInterval: TimeInterval { 120 }

    /// Extra space above the first shelf, below the tab bar or the navigation title.
    var topInset: CGFloat { 0 }

    /// The first screen of a tab starts its shelves just under the tab bar instead of below the system's larger inset.
    private var isTabRoot: Bool {
        navigationController?.viewControllers.first === self && navigationController?.tabBarController != nil
    }

    /// A screen embedded under another screen's header starts its shelves at its own top edge.
    var managesOwnInsets: Bool { false }

    /// Whether pressing and holding a card offers its menu.
    var offersContextMenu: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.remembersLastFocusedIndexPath = true
        collectionView.contentInsetAdjustmentBehavior = isTabRoot || managesOwnInsets ? .never : .automatic
        if isTabRoot {
            collectionView.contentInset.top = TVMetrics.tabBarClearance
        }
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        stateView.translatesAutoresizingMaskIntoConstraints = false
        stateView.isHidden = true
        view.addSubview(stateView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stateView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stateView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        configureDataSource()
        setContentScrollView(collectionView, for: .top)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let lastLoad, Date().timeIntervalSince(lastLoad) < refreshInterval / 2 { return }
        reload()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startRefreshing()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopRefreshing()
        TVLivePreview.shared.stop()
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        stateView.isHidden ? [collectionView] : [stateView]
    }

    /// Loads the shelves again. Subclasses override ``load()``.
    final func reload() {
        lastLoad = Date()
        Task { await load() }
    }

    func load() async {}

    func apply(_ shelves: [TVShelf]) {
        let visible = shelves.filter { !$0.items.isEmpty }
        let previous = items
        self.shelves = visible
        items = [:]
        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        for shelf in visible {
            snapshot.appendSections([shelf.id])
            let ids = shelf.items.map { identifier(shelf: shelf.id, item: $0) }
            var unique: [String] = []
            for (id, item) in zip(ids, shelf.items) where items[id] == nil {
                items[id] = item
                unique.append(id)
            }
            snapshot.appendItems(unique, toSection: shelf.id)
        }
        let changed = snapshot.itemIdentifiers.filter { id in previous[id] != nil && previous[id] != items[id] }
        snapshot.reconfigureItems(changed)
        dataSource.apply(snapshot, animatingDifferences: !previous.isEmpty)
        if !visible.isEmpty { stateView.hide() }
        setNeedsFocusUpdate()
    }

    func item(at indexPath: IndexPath) -> TVShelfItem? {
        dataSource.itemIdentifier(for: indexPath).flatMap { items[$0] }
    }

    /// What a click on a card does. Streams play, everything else opens.
    func didSelect(_ item: TVShelfItem) {
        TVRouter.open(item, from: self)
    }

    private func identifier(shelf: String, item: TVShelfItem) -> String {
        "\(shelf)|\(item.key)"
    }

    private func shelf(for section: Int) -> TVShelf? {
        guard let id = dataSource?.sectionIdentifier(for: section) else { return nil }
        return shelves.first { $0.id == id }
    }

    private func startRefreshing() {
        stopRefreshing()
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    private func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
            self.foregroundObserver = nil
        }
    }

    private func configureDataSource() {
        let streams = UICollectionView.CellRegistration<TVStreamCell, TVShelfItem> { [weak self] cell, indexPath, item in
            guard case .stream(let stream) = item else { return }
            let featured = self?.shelf(for: indexPath.section)?.style == .featured
            cell.configure(stream, isFavorite: FavoritesStore.shared.isFavorite(stream.userID), featured: featured)
        }
        let posters = UICollectionView.CellRegistration<TVPosterCell, TVShelfItem> { cell, _, item in
            guard case .category(let category) = item else { return }
            cell.configure(category)
        }
        let channels = UICollectionView.CellRegistration<TVChannelCell, TVShelfItem> { cell, _, item in
            guard case .channel(let channel) = item else { return }
            cell.configure(channel)
        }
        let videos = UICollectionView.CellRegistration<TVVideoCell, TVShelfItem> { cell, _, item in
            switch item {
            case .video(let video): cell.configure(video)
            case .clip(let clip): cell.configure(clip)
            default: break
            }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, id in
            guard let item = self?.items[id] else { return nil }
            switch item {
            case .stream: return collectionView.dequeueConfiguredReusableCell(using: streams, for: indexPath, item: item)
            case .category: return collectionView.dequeueConfiguredReusableCell(using: posters, for: indexPath, item: item)
            case .channel: return collectionView.dequeueConfiguredReusableCell(using: channels, for: indexPath, item: item)
            case .video, .clip: return collectionView.dequeueConfiguredReusableCell(using: videos, for: indexPath, item: item)
            }
        }
        let headers = UICollectionView.SupplementaryRegistration<TVSectionHeaderView>(elementKind: TVSectionHeaderView.kind) { [weak self] header, _, indexPath in
            header.configure(title: self?.shelf(for: indexPath.section)?.title ?? "")
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headers, for: indexPath)
        }
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] section, _ in
            guard let self, let shelf = self.shelf(for: section) else { return Self.rowSection(item: TVMetrics.Card.stream, captionHeight: 120, titled: false) }
            let titled = shelf.title != nil
            let layoutSection: NSCollectionLayoutSection
            switch shelf.style {
            case .featured: layoutSection = Self.rowSection(item: TVMetrics.Card.featured, captionHeight: 140, titled: titled)
            case .streams: layoutSection = Self.rowSection(item: TVMetrics.Card.stream, captionHeight: 120, titled: titled)
            case .videos: layoutSection = Self.rowSection(item: TVMetrics.Card.video, captionHeight: 120, titled: titled)
            case .categories: layoutSection = Self.rowSection(item: TVMetrics.Card.poster, captionHeight: 60, titled: titled)
            case .channels:
                layoutSection = Self.rowSection(item: CGSize(width: 220, height: TVMetrics.Card.avatar), captionHeight: 60, titled: titled)
            case .streamGrid: layoutSection = Self.gridSection(item: TVMetrics.Card.stream, captionHeight: 120, columns: 4, titled: titled)
            case .categoryGrid: layoutSection = Self.gridSection(item: TVMetrics.Card.poster, captionHeight: 60, columns: 6, titled: titled)
            }
            if section == 0 {
                layoutSection.contentInsets.top += self.topInset
            }
            return layoutSection
        }
    }

    private static func rowSection(item size: CGSize, captionHeight: CGFloat, titled: Bool) -> NSCollectionLayoutSection {
        let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(size.width), heightDimension: .absolute(size.height + captionHeight))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: itemSize, subitems: [NSCollectionLayoutItem(layoutSize: itemSize)])
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = TVMetrics.itemSpacing
        section.contentInsetsReference = .none
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: TVMetrics.horizontalInset, bottom: TVMetrics.shelfSpacing, trailing: TVMetrics.horizontalInset)
        if titled { section.boundarySupplementaryItems = [header()] }
        return section
    }

    private static func gridSection(item size: CGSize, captionHeight: CGFloat, columns: Int, titled: Bool) -> NSCollectionLayoutSection {
        let height = size.height + captionHeight
        let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(size.width), heightDimension: .absolute(height))
        let width = CGFloat(columns) * size.width
        let spacing = (1920 - 2 * TVMetrics.horizontalInset - width) / CGFloat(max(1, columns - 1))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height)),
            repeatingSubitem: NSCollectionLayoutItem(layoutSize: itemSize),
            count: columns
        )
        group.interItemSpacing = .fixed(spacing)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = TVMetrics.shelfSpacing
        section.contentInsetsReference = .none
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: TVMetrics.horizontalInset, bottom: TVMetrics.shelfSpacing, trailing: TVMetrics.horizontalInset)
        if titled { section.boundarySupplementaryItems = [header()] }
        return section
    }

    private static func header() -> NSCollectionLayoutBoundarySupplementaryItem {
        NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(TVMetrics.headerHeight)),
            elementKind: TVSectionHeaderView.kind,
            alignment: .top
        )
    }

    /// Called as a card comes on screen, for a grid that loads more near its end.
    func willShowItem(at indexPath: IndexPath) {}

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        willShowItem(at: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = item(at: indexPath) else { return }
        TVLivePreview.shared.stop()
        didSelect(item)
    }

    func collectionView(_ collectionView: UICollectionView, didUpdateFocusIn context: UICollectionViewFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        if let cell = context.nextFocusedItem as? TVStreamCell {
            TVLivePreview.shared.focus(cell)
        } else {
            TVLivePreview.shared.stop()
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard offersContextMenu, let indexPath = indexPaths.first, let item = item(at: indexPath) else { return nil }
        MidgarLog.info("tv: context menu for \(item.key)", category: .app)
        let actions = TVRouter.contextActions(for: item, from: self)
        guard !actions.isEmpty else { return nil }
        TVLivePreview.shared.stop()
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: actions)
        }
    }
}
