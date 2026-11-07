import UIKit
import EmbrCore
import MidgarCore

/// Picks a channel whose chat to keep open: the followed channels live now, the favorites, or any channel by name.
@MainActor
final class ChatPickerViewController: UIViewController {
    private enum Section: Int, CaseIterable {
        case results
        case live
        case favorites
    }

    private struct Item: Hashable {
        let section: Section
        let entry: ChatsModel.Entry
        let detail: String?
    }

    private let api: TwitchAPIProviding
    private let choose: (ChatsModel.Entry) -> Void
    private let searchController = UISearchController(searchResultsController: nil)
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var results: [Item] = []
    private var searchTask: Task<Void, Never>?

    init(api: TwitchAPIProviding = AppContainer.shared.api, choose: @escaping (ChatsModel.Entry) -> Void) {
        self.api = api
        self.choose = choose
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Add a Chat")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = String(localized: "Search channels")
        searchController.searchBar.autocapitalizationType = .none
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        setUpList()
        apply()
    }

    private func setUpList() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.backgroundColor = Theme.background
        config.headerMode = .supplementary
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: StreamListLayout.readableList(using: config))
        collectionView.backgroundColor = Theme.background
        collectionView.keyboardDismissMode = .onDrag
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let row = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            var content = cell.defaultContentConfiguration()
            content.text = item.entry.name
            content.secondaryText = item.detail
            content.secondaryTextProperties.color = Theme.secondaryText
            content.image = UIImage(systemName: item.section == .live ? "dot.radiowaves.left.and.right" : "bubble.left")
            content.imageProperties.tintColor = item.section == .live ? Theme.liveDot : Theme.accent
            cell.contentConfiguration = content
            cell.backgroundConfiguration = Theme.groupedRowBackground()
            cell.accessories = ChatsModel.shared.contains(item.entry.id) ? [.checkmark()] : []
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: row, for: indexPath, item: item)
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] cell, _, indexPath in
            var content = UIListContentConfiguration.groupedHeader()
            content.text = self?.dataSource.sectionIdentifier(for: indexPath.section).map(Self.title)
            cell.contentConfiguration = content
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
    }

    private static func title(_ section: Section) -> String {
        switch section {
        case .results: String(localized: "Channels")
        case .live: String(localized: "Live Now")
        case .favorites: String(localized: "Favorites")
        }
    }

    private func apply() {
        let searching = !(searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        if searching {
            if !results.isEmpty {
                snapshot.appendSections([.results])
                snapshot.appendItems(results, toSection: .results)
            }
        } else {
            let live = FollowedLiveService.shared.liveStreams.map { stream in
                Item(section: .live, entry: ChatsModel.Entry(id: stream.userID, login: stream.userLogin, name: stream.userName.isEmpty ? stream.userLogin : stream.userName), detail: stream.gameName.isEmpty ? nil : stream.gameName)
            }
            let liveIDs = Set(live.map(\.entry.id))
            let favorites = FavoritesStore.shared.channels
                .filter { !liveIDs.contains($0.id) }
                .map { Item(section: .favorites, entry: ChatsModel.Entry(id: $0.id, login: $0.login, name: $0.name), detail: nil) }
            if !live.isEmpty {
                snapshot.appendSections([.live])
                snapshot.appendItems(live, toSection: .live)
            }
            if !favorites.isEmpty {
                snapshot.appendSections([.favorites])
                snapshot.appendItems(favorites, toSection: .favorites)
            }
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func search(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            apply()
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self else { return }
            do {
                let page = try await self.api.searchChannels(query: trimmed, liveOnly: false, after: nil, first: 20)
                guard !Task.isCancelled else { return }
                self.results = page.items.map { channel in
                    Item(
                        section: .results,
                        entry: ChatsModel.Entry(id: channel.id, login: channel.broadcasterLogin, name: channel.broadcasterName),
                        detail: channel.isLive ? String(localized: "Live") + (channel.gameName.isEmpty ? "" : " · \(channel.gameName)") : nil
                    )
                }
                self.apply()
            } catch {
                MidgarLog.notice("chat picker search failed: \(error)", category: .api)
            }
        }
    }
}

extension ChatPickerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        search(searchController.searchBar.text ?? "")
    }
}

extension ChatPickerViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.selection()
        choose(item.entry)
        dismiss(animated: true)
    }
}
