import UIKit
import Combine
import EmbrCore

@MainActor
final class SearchViewController: UIViewController {
    private enum Section: Int, Hashable, CaseIterable {
        case channels
        case categories

        var title: String {
            switch self {
            case .channels: return String(localized: "Channels")
            case .categories: return String(localized: "Categories")
            }
        }
    }

    private enum Item: Hashable {
        case channel(ChannelInfo)
        case category(GameCategory)
    }

    private let api: TwitchAPIProviding
    private let searchController = UISearchController(searchResultsController: nil)
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let emptyView = EmptyStateView(symbol: "magnifyingglass", message: String(localized: "Search for channels and categories."))
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.color = Theme.secondaryText
        return indicator
    }()

    private var searchTask: Task<Void, Never>?
    private var debounce: Task<Void, Never>?

    init(api: TwitchAPIProviding = TwitchAPIClient.shared) {
        self.api = api
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Search")
        tabBarItem = UITabBarItem(title: String(localized: "Search"), image: UIImage(systemName: "magnifyingglass"), selectedImage: UIImage(systemName: "magnifyingglass"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        setUpSearch()
        setUpCollectionView()
        setUpDataSource()
        setUpEmptyState()
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (controller: SearchViewController, _) in
            var snapshot = controller.dataSource.snapshot()
            guard !snapshot.sectionIdentifiers.isEmpty else { return }
            snapshot.reloadSections(snapshot.sectionIdentifiers)
            controller.dataSource.apply(snapshot, animatingDifferences: false)
        }
        #if DEBUG
        if let query = ScreenshotHarness.searchQuery {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                self.searchController.isActive = true
                self.searchController.searchBar.text = query
                self.performSearch(query)
            }
        }
        #endif
    }

    /// ⌘F lands here with the field ready to type into.
    func focusSearchField() {
        navigationController?.popToRootViewController(animated: false)
        searchController.isActive = true
        DispatchQueue.main.async { [weak self] in
            self?.searchController.searchBar.becomeFirstResponder()
        }
    }

    func scrollToTop() {
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: true)
    }

    private func setUpSearch() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = String(localized: "Channels & categories")
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.scopeButtonTitles = [String(localized: "All"), String(localized: "Live")]
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        if !OrientationCoordinator.isPhone {
            navigationItem.preferredSearchBarPlacement = .stacked
        }
        definesPresentationContext = true
    }

    private func setUpCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.preservesSuperviewLayoutMargins = !OrientationCoordinator.isPhone
        collectionView.delegate = self
        collectionView.dragDelegate = self
        collectionView.keyboardDismissMode = .onDrag
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] index, environment in
            MainActor.assumeIsolated {
                let section = self?.dataSource?.sectionIdentifier(for: index) ?? .channels
                let grid = StreamListLayout.usesCards(environment.traitCollection)
                if section == .categories {
                    let layoutSection = StreamListLayout.categoriesSection(environment: environment)
                    if let header = self?.headerItem() {
                        StreamListLayout.attachHeader(header, to: layoutSection)
                    }
                    return layoutSection
                }
                guard grid else {
                    var config = UICollectionLayoutListConfiguration(appearance: .plain)
                    config.backgroundColor = .clear
                    config.headerMode = .supplementary
                    return NSCollectionLayoutSection.list(using: config, layoutEnvironment: environment)
                }
                let layoutSection = StreamListLayout.channelRowsSection(environment: environment, estimatedHeight: 60)
                layoutSection.contentInsets.bottom = 16
                if let header = self?.headerItem() {
                    StreamListLayout.attachHeader(header, to: layoutSection)
                }
                return layoutSection
            }
        }
    }

    private var usesGrid: Bool { StreamListLayout.usesCards(traitCollection) }

    private func headerItem() -> NSCollectionLayoutBoundarySupplementaryItem {
        NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(36)),
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
    }

    private func setUpDataSource() {
        let channelRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, ChannelInfo> { [weak self] cell, _, channel in
            var content = cell.defaultContentConfiguration()
            if self?.usesGrid == true {
                content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
            }
            content.text = channel.broadcasterName
            content.secondaryText = channel.gameName.isEmpty ? channel.title : channel.gameName
            content.textProperties.color = Theme.primaryText
            content.secondaryTextProperties.color = Theme.secondaryText
            content.image = UIImage(systemName: channel.isLive ? "dot.radiowaves.left.and.right" : "play.tv")
            content.imageProperties.tintColor = channel.isLive ? Theme.liveDot : Theme.secondaryText
            cell.contentConfiguration = content
            var background = UIBackgroundConfiguration.listCell()
            background.backgroundColor = .clear
            if self?.usesGrid == true {
                background.cornerRadius = 10
                background.backgroundInsets = NSDirectionalEdgeInsets(top: 0, leading: -8, bottom: 0, trailing: -8)
            }
            cell.backgroundConfiguration = background
            cell.accessories = [.disclosureIndicator()]
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = channel.isLive ? String(localized: "\(channel.broadcasterName), live") : channel.broadcasterName
            cell.accessibilityTraits = .button
        }
        let categoryRegistration = UICollectionView.CellRegistration<CategoryCell, GameCategory> { cell, _, category in
            cell.configure(with: category)
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] header, _, indexPath in
            guard let self else { return }
            let section = self.dataSource.snapshot().sectionIdentifiers[indexPath.section]
            var content = header.defaultContentConfiguration()
            if self.usesGrid {
                content.directionalLayoutMargins.leading = 0
            }
            content.text = section.title
            content.textProperties.color = Theme.secondaryText
            content.textProperties.font = .systemFont(ofSize: 13, weight: .semibold)
            header.contentConfiguration = content
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .channel(let channel):
                return collectionView.dequeueConfiguredReusableCell(using: channelRegistration, for: indexPath, item: channel)
            case .category(let category):
                return collectionView.dequeueConfiguredReusableCell(using: categoryRegistration, for: indexPath, item: category)
            }
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    private func setUpEmptyState() {
        emptyView.translatesAutoresizingMaskIntoConstraints = false
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
    }

    private func performSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchTask?.cancel()
            applyResults(channels: [], categories: [])
            emptyView.setMessage(String(localized: "Search for channels and categories."))
            emptyView.isHidden = false
            return
        }
        searchTask?.cancel()
        let api = self.api
        let liveOnly = searchController.searchBar.selectedScopeButtonIndex == 1
        emptyView.isHidden = true
        loadingIndicator.startAnimating()
        searchTask = Task { [weak self] in
            async let channelsResult = try? api.searchChannels(query: trimmed, liveOnly: liveOnly, after: nil, first: 12)
            async let categoriesResult = liveOnly ? nil : (try? api.searchCategories(query: trimmed, after: nil, first: 12))
            let channelsPage = await channelsResult
            let categoriesPage = await categoriesResult
            if Task.isCancelled { return }
            guard let self else { return }
            self.loadingIndicator.stopAnimating()
            let channels = channelsPage?.items ?? []
            let categories = categoriesPage?.items ?? []
            self.applyResults(channels: channels, categories: categories)
            if channelsPage == nil && categoriesPage == nil {
                self.emptyView.setMessage(String(localized: "Couldn't search — check your connection."))
            } else {
                self.emptyView.setMessage(String(localized: "No results for \"\(trimmed)\"."))
            }
            self.emptyView.isHidden = !(channels.isEmpty && categories.isEmpty)
        }
    }

    private func applyResults(channels: [ChannelInfo], categories: [GameCategory]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        if !channels.isEmpty {
            snapshot.appendSections([.channels])
            snapshot.appendItems(channels.map(Item.channel), toSection: .channels)
        }
        if !categories.isEmpty {
            snapshot.appendSections([.categories])
            snapshot.appendItems(categories.map(Item.category), toSection: .categories)
        }
        dataSource.apply(snapshot, animatingDifferences: true)
    }
}

extension SearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let text = searchController.searchBar.text ?? ""
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            self?.performSearch(text)
        }
    }
}

extension SearchViewController: UICollectionViewDragDelegate {
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard case let .channel(channel)? = dataSource.itemIdentifier(for: indexPath) else { return [] }
        return ChannelActions.dragItems(login: channel.broadcasterLogin, name: channel.broadcasterName)
    }
}

extension SearchViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .channel(let channel):
            navigationController?.pushViewController(ChannelViewController(channel: channel), animated: true)
        case .category(let category):
            navigationController?.pushViewController(TopViewController(mode: .game(category), api: api), animated: true)
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard case let .channel(channel)? = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return ChannelActions.configuration(login: channel.broadcasterLogin, broadcasterID: channel.id, name: channel.broadcasterName, from: self)
    }
}
