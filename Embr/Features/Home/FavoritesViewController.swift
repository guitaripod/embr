import UIKit
import Combine
import EmbrCore

/// The channels starred in Embr: live ones first as stream cards, the rest as a list. Unlike
/// Following it needs no Twitch account, so it is the one personal list a guest has.
@MainActor
final class FavoritesViewController: UIViewController {
    private enum Section: Hashable { case live, offline }
    private enum Item: Hashable {
        case stream(LiveStream)
        case channel(FavoriteChannel)
    }

    private let favorites: FavoritesStore
    private let monitor: FavoritesLiveMonitor

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let refreshControl = UIRefreshControl()
    private let emptyView = EmptyStateView(
        symbol: "star",
        message: String(localized: "Tap the star on any channel, or press and hold a stream, to keep it here. No account needed.")
    )
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.color = Theme.secondaryText
        return indicator
    }()
    private var cancellables = Set<AnyCancellable>()

    init(favorites: FavoritesStore = .shared, monitor: FavoritesLiveMonitor = .shared) {
        self.favorites = favorites
        self.monitor = monitor
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Favorites")
        tabBarItem = UITabBarItem(
            title: String(localized: "Favorites"),
            image: UIImage(systemName: "star"),
            selectedImage: UIImage(systemName: "star.fill")
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .automatic
        setUpCollectionView()
        setUpDataSource()
        setUpStates()
        bind()
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        monitor.refresh(force: false)
    }

    func scrollToTop() {
        guard collectionView.numberOfSections > 0 else { return }
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: true)
    }

    private func bind() {
        monitor.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.render() }
            }
            .store(in: &cancellables)
        favorites.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.render() }
            }
            .store(in: &cancellables)
    }

    private func setUpCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        collectionView.refreshControl = refreshControl
        refreshControl.tintColor = Theme.accent
        refreshControl.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            MainActor.assumeIsolated {
                if self?.dataSource?.sectionIdentifier(for: sectionIndex) == .offline {
                    return Self.offlineSection()
                }
                return Self.liveSection(environment: environment)
            }
        }
    }

    private static func headerItem() -> NSCollectionLayoutBoundarySupplementaryItem {
        NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(34)),
            elementKind: SectionHeaderView.elementKind, alignment: .top)
    }

    private static func liveSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let section = StreamListLayout.streamsSection(environment: environment)
        section.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 0, bottom: 10, trailing: 0)
        section.boundarySupplementaryItems = [headerItem()]
        return section
    }

    private static func offlineSection() -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(56)))
        let group = NSCollectionLayoutGroup.vertical(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(56)),
            subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 0, bottom: 16, trailing: 0)
        section.boundarySupplementaryItems = [headerItem()]
        return section
    }

    private func setUpDataSource() {
        let streamRegistration = UICollectionView.CellRegistration<StreamCell, LiveStream> { [weak self] cell, _, stream in
            cell.configure(with: stream, avatarURL: self?.monitor.avatars[stream.userID])
        }
        let channelRegistration = UICollectionView.CellRegistration<FollowedChannelCell, FavoriteChannel> { [weak self] cell, _, channel in
            cell.configure(with: Self.listing(for: channel), avatarURL: self?.monitor.avatars[channel.id])
        }
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .stream(let stream):
                return collectionView.dequeueConfiguredReusableCell(using: streamRegistration, for: indexPath, item: stream)
            case .channel(let channel):
                return collectionView.dequeueConfiguredReusableCell(using: channelRegistration, for: indexPath, item: channel)
            }
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<SectionHeaderView>(elementKind: SectionHeaderView.elementKind) { [weak self] view, _, indexPath in
            let section = self?.dataSource.sectionIdentifier(for: indexPath.section)
            view.configure(title: section == .offline ? String(localized: "Channels") : String(localized: "Live"))
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
        }
    }

    private func setUpStates() {
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
    }

    private func render() {
        guard isViewLoaded else { return }
        let live = monitor.liveStreams
        let liveIDs = Set(live.map(\.userID))
        let offline = favorites.channels
            .filter { !liveIDs.contains($0.id) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        if !live.isEmpty {
            snapshot.appendSections([.live])
            snapshot.appendItems(live.map(Item.stream), toSection: .live)
        }
        if monitor.status == .loaded, !offline.isEmpty {
            snapshot.appendSections([.offline])
            snapshot.appendItems(offline.map(Item.channel), toSection: .offline)
        }
        let shown = Set(dataSource.snapshot().itemIdentifiers)
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter(shown.contains))
        dataSource.apply(snapshot, animatingDifferences: view.window != nil)

        if monitor.status != .loading { refreshControl.endRefreshing() }
        applyState(hasFavorites: !favorites.channels.isEmpty, showsItems: snapshot.numberOfItems > 0)
    }

    private func applyState(hasFavorites: Bool, showsItems: Bool) {
        switch monitor.status {
        case .loading where !showsItems && hasFavorites:
            loadingIndicator.startAnimating()
            emptyView.isHidden = true
        case .failed(let message) where !showsItems:
            loadingIndicator.stopAnimating()
            emptyView.setMessage(message)
            emptyView.onRetry = { [weak self] in self?.monitor.refresh(force: true) }
            emptyView.isHidden = false
        default:
            loadingIndicator.stopAnimating()
            emptyView.setMessage(String(localized: "Tap the star on any channel, or press and hold a stream, to keep it here. No account needed."))
            emptyView.onRetry = nil
            emptyView.isHidden = hasFavorites
        }
    }

    @objc private func pullToRefresh() {
        Haptics.selection()
        monitor.refresh(force: true)
    }

    private static func listing(for channel: FavoriteChannel) -> FollowedChannel {
        FollowedChannel(id: channel.id, broadcasterLogin: channel.login, broadcasterName: channel.displayName, followedAt: channel.addedAt)
    }

    private static func channelInfo(for channel: FavoriteChannel) -> ChannelInfo {
        ChannelInfo(id: channel.id, broadcasterLogin: channel.login, broadcasterName: channel.displayName, gameID: "", gameName: "", title: "", language: "")
    }
}

extension FavoritesViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.selection()
        switch item {
        case .stream(let stream):
            navigationController?.pushViewController(ChannelViewController(channel: StreamRouting.channel(from: stream)), animated: true)
        case .channel(let channel):
            navigationController?.pushViewController(ChannelViewController(channel: Self.channelInfo(for: channel)), animated: true)
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .stream(let stream):
            return ChannelActions.configuration(login: stream.userLogin, broadcasterID: stream.userID, name: stream.userName, from: self)
        case .channel(let channel):
            return ChannelActions.configuration(login: channel.login, broadcasterID: channel.id, name: channel.displayName, from: self)
        case .none:
            return nil
        }
    }
}
