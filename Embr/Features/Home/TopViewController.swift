import UIKit
import Combine
import EmbrCore

@MainActor
final class TopViewController: UIViewController {
    enum Mode: Equatable {
        case top
        case game(GameCategory)
    }

    private enum Section: Hashable { case recent, main }
    private enum Item: Hashable {
        case stream(LiveStream)
        case category(GameCategory)
        case recentChannel(WatchedChannel)
    }

    private let mode: Mode
    private let api: TwitchAPIProviding
    private let history: WatchHistoryStore

    private var recentChannels: [WatchedChannel] = []
    private var avatars: [String: URL] = [:]
    private var showsRecentRail: Bool { mode == .top }

    private let segmented = UISegmentedControl(items: ["Streams", "Categories"])
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let refreshControl = UIRefreshControl()
    private let emptyView = EmptyStateView(symbol: "tv.slash", message: "Nothing live here right now.")
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.color = Theme.secondaryText
        return indicator
    }()

    private static let emptyStreamsMessage = "Nothing live here right now."
    private static let emptyCategoriesMessage = "No categories to show."

    private var streamsViewModel: StreamListViewModel!
    private var cancellables = Set<AnyCancellable>()

    private var categories: [GameCategory] = []
    private var categoryCursor: String?
    private var categoryHasMore = true
    private var categoryLoading = false
    private var categoryTask: Task<Void, Never>?

    private var showingCategories = false

    init(mode: Mode = .top, api: TwitchAPIProviding = TwitchAPIClient.shared, history: WatchHistoryStore = .shared) {
        self.mode = mode
        self.api = api
        self.history = history
        super.init(nibName: nil, bundle: nil)
        switch mode {
        case .top:
            title = "Top"
            tabBarItem = UITabBarItem(title: "Top", image: UIImage(systemName: "chart.line.uptrend.xyaxis"), selectedImage: UIImage(systemName: "chart.line.uptrend.xyaxis"))
            streamsViewModel = StreamListViewModel(kind: .top, api: api)
        case .game(let category):
            title = category.name
            streamsViewModel = StreamListViewModel(kind: .game(id: category.id), api: api)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        setUpSegmentedControlIfNeeded()
        setUpCollectionView()
        setUpDataSource()
        setUpEmptyState()
        bindStreams()
        bindHistory()
        streamsViewModel.load()
    }

    private func bindHistory() {
        guard showsRecentRail else { return }
        recentChannels = history.recent
        loadRecentAvatars()
        history.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] channels in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.recentChannels = channels
                    self.loadRecentAvatars()
                    if !self.showingCategories { self.applyStreams(self.streamsViewModel.currentStreams) }
                }
            }
            .store(in: &cancellables)
    }

    private func loadRecentAvatars() {
        let missing = recentChannels.map(\.id).filter { avatars[$0] == nil }
        guard !missing.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let users = try? await self.api.users(ids: missing) else { return }
            var changed = false
            for user in users {
                if let url = user.profileImageURL { self.avatars[user.id] = url; changed = true }
            }
            guard changed, !self.showingCategories else { return }
            self.reconfigureRecent()
        }
    }

    private func reconfigureRecent() {
        var snapshot = dataSource.snapshot()
        guard snapshot.sectionIdentifiers.contains(.recent) else { return }
        snapshot.reconfigureItems(snapshot.itemIdentifiers(inSection: .recent))
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func scrollToTop() {
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: true)
    }

    private func setUpSegmentedControlIfNeeded() {
        guard mode == .top else { return }
        segmented.selectedSegmentIndex = 0
        segmented.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        navigationItem.titleView = segmented
    }

    private func makeStreamsLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            MainActor.assumeIsolated {
                if self?.dataSource?.sectionIdentifier(for: sectionIndex) == .recent {
                    return Self.recentRailSection()
                }
                return StreamListLayout.streamsSection(environment: environment)
            }
        }
    }

    private static func recentRailSection() -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalHeight(1.0)))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(66), heightDimension: .absolute(86)),
            subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 10
        section.orthogonalScrollingBehavior = .continuous
        section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(28)),
            elementKind: SectionHeaderView.elementKind, alignment: .top)
        section.boundarySupplementaryItems = [header]
        return section
    }

    private func setUpCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeStreamsLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.refreshControl = refreshControl
        refreshControl.tintColor = Theme.accent
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setUpDataSource() {
        let streamRegistration = UICollectionView.CellRegistration<StreamCell, LiveStream> { [weak self] cell, _, stream in
            cell.configure(with: stream, avatarURL: self?.streamsViewModel.avatarURL(for: stream.userID))
        }
        let categoryRegistration = UICollectionView.CellRegistration<CategoryCell, GameCategory> { cell, _, category in
            cell.configure(with: category)
        }
        let recentRegistration = UICollectionView.CellRegistration<RecentChannelCell, WatchedChannel> { [weak self] cell, _, channel in
            cell.configure(with: channel, avatarURL: self?.avatars[channel.id])
        }
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .stream(let stream):
                return collectionView.dequeueConfiguredReusableCell(using: streamRegistration, for: indexPath, item: stream)
            case .category(let category):
                return collectionView.dequeueConfiguredReusableCell(using: categoryRegistration, for: indexPath, item: category)
            case .recentChannel(let channel):
                return collectionView.dequeueConfiguredReusableCell(using: recentRegistration, for: indexPath, item: channel)
            }
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<SectionHeaderView>(elementKind: SectionHeaderView.elementKind) { view, _, _ in
            view.configure(title: "Recently Watched")
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    private func setUpEmptyState() {
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.isHidden = true
        view.addSubview(emptyView)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            emptyView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        loadingIndicator.startAnimating()
    }

    private var hasContent: Bool {
        !streamsViewModel.currentStreams.isEmpty
    }

    private func bindStreams() {
        streamsViewModel.streamsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] streams in
                MainActor.assumeIsolated {
                    guard let self, !self.showingCategories else { return }
                    self.applyStreams(streams)
                }
            }
            .store(in: &cancellables)
        streamsViewModel.loadingSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                MainActor.assumeIsolated {
                    guard let self, !self.showingCategories else { return }
                    if loading {
                        if !self.hasContent {
                            self.emptyView.isHidden = true
                            self.loadingIndicator.startAnimating()
                        }
                    } else {
                        self.loadingIndicator.stopAnimating()
                        self.refreshControl.endRefreshing()
                    }
                }
            }
            .store(in: &cancellables)
        streamsViewModel.errorSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                MainActor.assumeIsolated {
                    guard let self, !self.showingCategories else { return }
                    self.loadingIndicator.stopAnimating()
                    self.refreshControl.endRefreshing()
                    if !self.hasContent {
                        self.emptyView.setMessage(message)
                        self.emptyView.onRetry = { [weak self] in self?.streamsViewModel.load() }
                        self.emptyView.isHidden = false
                    }
                }
            }
            .store(in: &cancellables)
        streamsViewModel.avatarsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.reconfigureStreamAvatars() }
            }
            .store(in: &cancellables)
    }

    private func reconfigureStreamAvatars() {
        guard !showingCategories else { return }
        var snapshot = dataSource.snapshot()
        let streamItems = snapshot.itemIdentifiers.filter { if case .stream = $0 { return true } else { return false } }
        guard !streamItems.isEmpty else { return }
        snapshot.reconfigureItems(streamItems)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func applyStreams(_ streams: [LiveStream]) {
        loadingIndicator.stopAnimating()
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        if showsRecentRail, !recentChannels.isEmpty {
            snapshot.appendSections([.recent])
            snapshot.appendItems(recentChannels.map(Item.recentChannel), toSection: .recent)
        }
        snapshot.appendSections([.main])
        snapshot.appendItems(streams.map(Item.stream), toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: true)
        emptyView.setMessage(Self.emptyStreamsMessage)
        emptyView.onRetry = nil
        emptyView.isHidden = !streams.isEmpty
    }

    private func applyCategories() {
        loadingIndicator.stopAnimating()
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(categories.map(Item.category), toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: true)
        emptyView.setMessage(Self.emptyCategoriesMessage)
        emptyView.onRetry = nil
        emptyView.isHidden = !categories.isEmpty
    }

    @objc private func segmentChanged() {
        Haptics.selection()
        showingCategories = segmented.selectedSegmentIndex == 1
        if showingCategories {
            collectionView.setCollectionViewLayout(StreamListLayout.grid(columns: 3), animated: false)
            if categories.isEmpty { loadCategories(replacing: true) } else { applyCategories() }
        } else {
            collectionView.setCollectionViewLayout(makeStreamsLayout(), animated: false)
            applyStreams(streamsViewModel.currentStreams)
        }
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false)
    }

    @objc private func refresh() {
        Haptics.selection()
        if showingCategories {
            loadCategories(replacing: true)
        } else {
            streamsViewModel.load()
        }
    }

    private func loadCategories(replacing: Bool) {
        guard !categoryLoading else { return }
        if replacing {
            categoryCursor = nil
            categoryHasMore = true
        }
        guard categoryHasMore else { return }
        categoryLoading = true
        if showingCategories, categories.isEmpty {
            emptyView.isHidden = true
            loadingIndicator.startAnimating()
        }
        categoryTask?.cancel()
        categoryTask = Task { [weak self] in
            guard let self else { return }
            defer { self.categoryLoading = false; self.refreshControl.endRefreshing() }
            do {
                let page = try await self.api.topCategories(after: replacing ? nil : self.categoryCursor, first: 30)
                if Task.isCancelled { return }
                self.categoryCursor = page.cursor
                self.categoryHasMore = page.cursor != nil
                if replacing {
                    self.categories = page.items
                } else {
                    let known = Set(self.categories.map(\.id))
                    self.categories.append(contentsOf: page.items.filter { !known.contains($0.id) })
                }
                if self.showingCategories { self.applyCategories() }
            } catch {
                if Task.isCancelled { return }
                AppLogger.shared.warn("Top categories load failed: \(error)", category: .api)
                guard self.showingCategories, self.categories.isEmpty else { return }
                self.loadingIndicator.stopAnimating()
                self.emptyView.setMessage("Couldn't load categories.")
                self.emptyView.onRetry = { [weak self] in self?.loadCategories(replacing: true) }
                self.emptyView.isHidden = false
            }
        }
    }
}

extension TopViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.selection()
        switch item {
        case .stream(let stream):
            navigationController?.pushViewController(ChannelViewController(channel: StreamRouting.channel(from: stream)), animated: true)
        case .category(let category):
            navigationController?.pushViewController(TopViewController(mode: .game(category), api: api), animated: true)
        case .recentChannel(let channel):
            navigationController?.pushViewController(ChannelViewController(channel: StreamRouting.channel(from: channel)), animated: true)
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .stream(let stream):
            return ChannelActions.configuration(login: stream.userLogin, broadcasterID: stream.userID, name: stream.userName, from: self)
        case .recentChannel(let channel):
            return ChannelActions.configuration(login: channel.login, broadcasterID: channel.id, name: channel.displayName, from: self)
        default:
            return nil
        }
    }
}

extension TopViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let mainItems = indexPaths.filter { dataSource.sectionIdentifier(for: $0.section) == .main }
        guard let max = mainItems.map(\.item).max() else { return }
        let count = dataSource.snapshot().numberOfItems(inSection: .main)
        guard max >= count - 6 else { return }
        if showingCategories {
            loadCategories(replacing: false)
        } else {
            streamsViewModel.loadMore()
        }
    }
}
