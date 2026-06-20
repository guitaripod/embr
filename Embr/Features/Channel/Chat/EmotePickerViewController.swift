import UIKit
import SDWebImage
import EmbrCore

@MainActor
final class EmotePickerViewController: UIViewController {
    private enum Section: Int, Hashable, CaseIterable {
        case channel
        case global

        var title: String {
            switch self {
            case .channel: return "Channel Emotes"
            case .global: return "Global Emotes"
            }
        }
    }

    private let channelEmotes: [Emote]
    private let globalEmotes: [Emote]
    private let images: ImageLoading
    private let onSelect: (String) -> Void

    private let searchField = UISearchTextField()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Emote>!

    init(catalog: EmoteCatalog, images: ImageLoading = AppContainer.shared.images, onSelect: @escaping (String) -> Void) {
        self.channelEmotes = catalog.channel.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
        self.globalEmotes = catalog.global.values.sorted { $0.name.lowercased() < $1.name.lowercased() }
        self.images = images
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Emotes"
        setUpSearch()
        setUpCollectionView()
        setUpDataSource()
        apply(filter: "")
    }

    private func setUpSearch() {
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = "Search emotes"
        searchField.autocapitalizationType = .none
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        view.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    @objc private func searchChanged() {
        apply(filter: searchField.text ?? "")
    }

    private func setUpCollectionView() {
        let layout = UICollectionViewCompositionalLayout { _, environment in
            let columns = max(5, Int(environment.container.effectiveContentSize.width / 64))
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                heightDimension: .fractionalHeight(1.0)
            ))
            item.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(56)),
                repeatingSubitem: item,
                count: columns
            )
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
            section.boundarySupplementaryItems = [
                NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(32)),
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                )
            ]
            return section
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.keyboardDismissMode = .onDrag
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setUpDataSource() {
        let registration = UICollectionView.CellRegistration<EmoteGridCell, Emote> { [weak self] cell, _, emote in
            guard let self else { return }
            cell.configure(with: emote, images: self.images)
        }
        let header = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { [weak self] view, _, indexPath in
            guard let self, let section = self.dataSource.sectionIdentifier(for: indexPath.section) else { return }
            var content = view.defaultContentConfiguration()
            content.text = section.title
            content.textProperties.color = Theme.secondaryText
            content.textProperties.font = .systemFont(ofSize: 13, weight: .semibold)
            view.contentConfiguration = content
        }
        dataSource = UICollectionViewDiffableDataSource<Section, Emote>(collectionView: collectionView) { collectionView, indexPath, emote in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: emote)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }
    }

    private func apply(filter: String) {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let channel = query.isEmpty ? channelEmotes : channelEmotes.filter { $0.name.lowercased().contains(query) }
        let global = query.isEmpty ? globalEmotes : globalEmotes.filter { $0.name.lowercased().contains(query) }
        var snapshot = NSDiffableDataSourceSnapshot<Section, Emote>()
        if !channel.isEmpty { snapshot.appendSections([.channel]); snapshot.appendItems(channel, toSection: .channel) }
        if !global.isEmpty { snapshot.appendSections([.global]); snapshot.appendItems(global, toSection: .global) }
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

extension EmotePickerViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let emote = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.selection()
        onSelect(emote.name)
    }
}

@MainActor
private final class EmoteGridCell: UICollectionViewCell {
    private let imageView = SDAnimatedImageView()
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        contentView.layer.cornerRadius = 8
        contentView.layer.cornerCurve = .continuous
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imageView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.78),
            imageView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.78)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? Theme.surfaceElevated : .clear }
    }

    func configure(with emote: Emote, images: ImageLoading) {
        loadTask?.cancel()
        imageView.image = nil
        imageView.autoPlayAnimatedImage = SettingsStore.shared.current.animateEmotes
        loadTask = Task { [weak self] in
            let image = await images.emoteImage(for: emote, scale: .x2)
            guard !Task.isCancelled else { return }
            self?.imageView.image = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        imageView.image = nil
        contentView.backgroundColor = .clear
    }
}
