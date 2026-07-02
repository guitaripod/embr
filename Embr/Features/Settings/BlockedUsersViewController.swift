import UIKit

@MainActor
final class BlockedUsersViewController: UIViewController {
    private var records: [String: BlockedUserRecord] = [:]
    private var order: [String] = []
    private var pendingUnblocks: Set<String> = []
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private let emptyLabel = UILabel()

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Blocked Users"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never
        setUpCollectionView()
        setUpEmptyLabel()
        setUpDataSource()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
    }

    private func setUpCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.backgroundColor = Theme.background
        config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self, let userID = self.dataSource.itemIdentifier(for: indexPath) else { return nil }
            let unblock = UIContextualAction(style: .destructive, title: "Unblock") { [weak self] _, _, completion in
                self?.unblock(userID: userID)
                completion(true)
            }
            return UISwipeActionsConfiguration(actions: [unblock])
        }
        let layout = UICollectionViewCompositionalLayout.list(using: config)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = Theme.background
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setUpEmptyLabel() {
        emptyLabel.text = "No blocked users.\nBlock someone from a chat message to hide them."
        emptyLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15))
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
    }

    private func setUpDataSource() {
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, String> { [weak self] cell, _, userID in
            var content = cell.defaultContentConfiguration()
            content.text = self?.records[userID]?.login ?? userID
            content.image = UIImage(systemName: "person.slash")
            cell.contentConfiguration = content
            cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
        }
        dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) { collectionView, indexPath, userID in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: userID)
        }
    }

    private func load() {
        Task { [weak self] in
            let fetched = await DatabaseManager.shared.blockedUsers()
            guard let self else { return }
            let users = fetched.filter { !self.pendingUnblocks.contains($0.userID) }
            self.records = Dictionary(users.map { ($0.userID, $0) }, uniquingKeysWith: { first, _ in first })
            var seen = Set<String>()
            self.order = users.map(\.userID).filter { seen.insert($0).inserted }
            self.applySnapshot()
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(order, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: true)
        emptyLabel.isHidden = !order.isEmpty
    }

    private func unblock(userID: String) {
        Haptics.selection()
        records[userID] = nil
        order.removeAll { $0 == userID }
        applySnapshot()
        pendingUnblocks.insert(userID)
        Task { [weak self] in
            await DatabaseManager.shared.removeBlockedUser(userID: userID)
            self?.pendingUnblocks.remove(userID)
        }
    }
}
