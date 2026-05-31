import UIKit
import Combine
import EmbrCore

@MainActor
final class TopViewController: UIViewController {
    enum Mode: Equatable {
        case top
        case game(GameCategory)
    }

    private enum Section: Hashable { case main }
    private enum Item: Hashable {
        case stream(LiveStream)
        case category(GameCategory)
    }

    private let mode: Mode
    private let api: TwitchAPIProviding

    private let segmented = UISegmentedControl(items: ["Streams", "Categories"])
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let refreshControl = UIRefreshControl()
    private let emptyView = EmptyStateView(symbol: "tv.slash", message: "Nothing live here right now.")

    private var streamsViewModel: StreamListViewModel!
    private var cancellables = Set<AnyCancellable>()

    private var categories: [GameCategory] = []
    private var categoryCursor: String?
    private var categoryHasMore = true
    private var categoryLoading = false
    private var categoryTask: Task<Void, Never>?

    private var showingCategories = false

    init(mode: Mode = .top, api: TwitchAPIProviding = TwitchAPIClient.shared) {
        self.mode = mode
        self.api = api
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
        streamsViewModel.load()
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

    private func setUpCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: StreamListLayout.make())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.refreshControl = refreshControl
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
        let streamRegistration = UICollectionView.CellRegistration<StreamCell, LiveStream> { cell, _, stream in
            cell.configure(with: stream)
        }
        let categoryRegistration = UICollectionView.CellRegistration<CategoryCell, GameCategory> { cell, _, category in
            cell.configure(with: category)
        }
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .stream(let stream):
                return collectionView.dequeueConfiguredReusableCell(using: streamRegistration, for: indexPath, item: stream)
            case .category(let category):
                return collectionView.dequeueConfiguredReusableCell(using: categoryRegistration, for: indexPath, item: category)
            }
        }
    }

    private func setUpEmptyState() {
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        emptyView.isHidden = true
        view.addSubview(emptyView)
        NSLayoutConstraint.activate([
            emptyView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
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
                    guard let self, !self.showingCategories, !loading else { return }
                    self.refreshControl.endRefreshing()
                }
            }
            .store(in: &cancellables)
        streamsViewModel.errorSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshControl.endRefreshing() }
            }
            .store(in: &cancellables)
    }

    private func applyStreams(_ streams: [LiveStream]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(streams.map(Item.stream), toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: true)
        emptyView.isHidden = !streams.isEmpty
    }

    private func applyCategories() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.main])
        snapshot.appendItems(categories.map(Item.category), toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: true)
        emptyView.isHidden = !categories.isEmpty
    }

    @objc private func segmentChanged() {
        showingCategories = segmented.selectedSegmentIndex == 1
        if showingCategories {
            collectionView.setCollectionViewLayout(StreamListLayout.grid(columns: 3), animated: false)
            if categories.isEmpty { loadCategories(replacing: true) } else { applyCategories() }
        } else {
            collectionView.setCollectionViewLayout(StreamListLayout.make(), animated: false)
            applyStreams(streamsViewModel.currentStreams)
        }
    }

    @objc private func refresh() {
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
            }
        }
    }
}

extension TopViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .stream(let stream):
            navigationController?.pushViewController(ChannelViewController(channel: StreamRouting.channel(from: stream)), animated: true)
        case .category(let category):
            navigationController?.pushViewController(TopViewController(mode: .game(category), api: api), animated: true)
        }
    }
}

extension TopViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard let max = indexPaths.map(\.item).max() else { return }
        let count = dataSource.snapshot().numberOfItems(inSection: .main)
        guard max >= count - 6 else { return }
        if showingCategories {
            loadCategories(replacing: false)
        } else {
            streamsViewModel.loadMore()
        }
    }
}
