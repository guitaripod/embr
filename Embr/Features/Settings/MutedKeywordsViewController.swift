import UIKit

@MainActor
final class MutedKeywordsViewController: UIViewController {
    private let store: SettingsStore
    private var keywords: [String]
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private let emptyLabel = UILabel()

    init(store: SettingsStore = .shared) {
        self.store = store
        self.keywords = store.current.mutedKeywordList
        super.init(nibName: nil, bundle: nil)
        title = "Muted Keywords"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .add,
            primaryAction: UIAction { [weak self] _ in self?.presentAddKeyword() }
        )
        setUpCollectionView()
        setUpEmptyLabel()
        setUpDataSource()
        applySnapshot()
    }

    private func setUpCollectionView() {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.backgroundColor = Theme.background
        config.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self, let keyword = self.dataSource.itemIdentifier(for: indexPath) else { return nil }
            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
                self?.remove(keyword)
                completion(true)
            }
            return UISwipeActionsConfiguration(actions: [delete])
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
        emptyLabel.text = "No muted keywords.\nTap + to hide any chat message containing a word or phrase."
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
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, String> { cell, _, keyword in
            var content = cell.defaultContentConfiguration()
            content.text = keyword
            content.image = UIImage(systemName: "character.bubble")
            cell.contentConfiguration = content
            cell.backgroundConfiguration = UIBackgroundConfiguration.listCell()
        }
        dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) { collectionView, indexPath, keyword in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: keyword)
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(keywords, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: true)
        emptyLabel.isHidden = !keywords.isEmpty
    }

    private func presentAddKeyword() {
        let alert = UIAlertController(
            title: "Mute a Keyword",
            message: "Messages containing this word or phrase will be hidden from chat.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Word or phrase"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.returnKeyType = .done
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text else { return }
            self.add(text)
        })
        present(alert, animated: true)
    }

    private func add(_ raw: String) {
        let keyword = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty,
              !keywords.contains(where: { $0.caseInsensitiveCompare(keyword) == .orderedSame }) else { return }
        keywords.append(keyword)
        keywords.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        Haptics.selection()
        persist()
        applySnapshot()
    }

    private func remove(_ keyword: String) {
        keywords.removeAll { $0 == keyword }
        Haptics.selection()
        persist()
        applySnapshot()
    }

    private func persist() {
        store.update { $0.mutedKeywords = keywords }
    }
}
