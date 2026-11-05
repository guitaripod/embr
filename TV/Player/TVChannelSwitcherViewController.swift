import UIKit
import EmbrCore

/// The player's custom overlay, reached by swiping up during a live stream: the channels live right now among
/// favorites and follows (or the top streams for someone with neither), one click to switch to one.
final class TVChannelSwitcherViewController: UIViewController, UICollectionViewDelegate {
    private let onPick: (LiveStream) -> Void
    private let titleLabel = UILabel()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private var streams: [String: LiveStream] = [:]

    init(onPick: @escaping (LiveStream) -> Void) {
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: 1920, height: 470)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.font = TVFont.sectionTitle
        titleLabel.textColor = .white
        titleLabel.text = String(localized: "Live Now")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let size = TVMetrics.Card.stream
        let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(size.width), heightDimension: .absolute(size.height + 120))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: itemSize, subitems: [NSCollectionLayoutItem(layoutSize: itemSize)])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = TVMetrics.itemSpacing
        section.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: TVMetrics.horizontalInset, bottom: 20, trailing: TVMetrics.horizontalInset)
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = .horizontal
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section, configuration: configuration))
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        let registration = UICollectionView.CellRegistration<TVStreamCell, LiveStream> { cell, _, stream in
            cell.configure(stream, isFavorite: FavoritesStore.shared.isFavorite(stream.userID), featured: false)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, id in
            guard let stream = self?.streams[id] else { return nil }
            return collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: stream)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 30),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: TVMetrics.horizontalInset),
            collectionView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        show(TVLiveDirectory.shared.liveNow)
        Task { [weak self] in
            await TVLiveDirectory.shared.refreshIfStale()
            var live = TVLiveDirectory.shared.liveNow
            if live.isEmpty {
                live = (try? await AppContainer.shared.api.topStreams(after: nil, first: 20).items) ?? []
                self?.titleLabel.text = String(localized: "Top Live")
            }
            self?.show(live)
        }
    }

    private func show(_ live: [LiveStream]) {
        streams = Dictionary(live.map { ($0.userID, $0) }, uniquingKeysWith: { first, _ in first })
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        var seen: Set<String> = []
        snapshot.appendItems(live.map(\.userID).filter { seen.insert($0).inserted })
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let id = dataSource.itemIdentifier(for: indexPath), let stream = streams[id] else { return }
        dismiss(animated: true)
        onPick(stream)
    }
}
