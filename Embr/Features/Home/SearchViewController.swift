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
            case .channels: return "Channels"
            case .categories: return "Categories"
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
    private let emptyView = EmptyStateView(symbol: "magnifyingglass", message: "Search for channels and categories.")
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
        title = "Search"
        tabBarItem = UITabBarItem(title: "Search", image: UIImage(systemName: "magnifyingglass"), selectedImage: UIImage(systemName: "magnifyingglass"))
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
    }

    func scrollToTop() {
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: true)
    }

    private func setUpSearch() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Channels & categories"
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.scopeButtonTitles = ["All", "Live"]
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func setUpCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
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
            let section = Section(rawValue: index) ?? .channels
            if section == .categories {
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0 / 3.0),
                    heightDimension: .fractionalHeight(1.0)
                ))
                item.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(220)),
                    repeatingSubitem: item,
                    count: 3
                )
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
                layoutSection.boundarySupplementaryItems = [self?.headerItem()].compactMap { $0 }
                return layoutSection
            }
            var config = UICollectionLayoutListConfiguration(appearance: .plain)
            config.backgroundColor = .clear
            config.headerMode = .supplementary
            return NSCollectionLayoutSection.list(using: config, layoutEnvironment: environment)
        }
    }

    private func headerItem() -> NSCollectionLayoutBoundarySupplementaryItem {
        NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(36)),
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
    }

    private func setUpDataSource() {
        let channelRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, ChannelInfo> { cell, _, channel in
            var content = cell.defaultContentConfiguration()
            content.text = channel.broadcasterName
            content.secondaryText = channel.gameName.isEmpty ? channel.title : channel.gameName
            content.textProperties.color = Theme.primaryText
            content.secondaryTextProperties.color = Theme.secondaryText
            content.image = UIImage(systemName: channel.isLive ? "dot.radiowaves.left.and.right" : "play.tv")
            content.imageProperties.tintColor = channel.isLive ? Theme.liveDot : Theme.secondaryText
            cell.contentConfiguration = content
            var background = UIBackgroundConfiguration.listCell()
            background.backgroundColor = .clear
            cell.backgroundConfiguration = background
            cell.accessories = [.disclosureIndicator()]
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = channel.isLive ? "\(channel.broadcasterName), live" : channel.broadcasterName
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
            emptyView.setMessage("Search for channels and categories.")
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
                self.emptyView.setMessage("Couldn't search — check your connection.")
            } else {
                self.emptyView.setMessage("No results for \"\(trimmed)\".")
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
