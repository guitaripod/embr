import UIKit
import Combine
import EmbrCore

@MainActor
final class FollowingViewController: UIViewController {
    private let auth: AuthService
    private let api: TwitchAPIProviding

    private var viewModel: StreamListViewModel?
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, LiveStream>!
    private let refreshControl = UIRefreshControl()
    private let emptyView = EmptyStateView(symbol: "heart.slash", message: "No followed channels are live right now.")
    private let signInView = EmptyStateView(symbol: "person.crop.circle.badge.exclamationmark", message: "Sign in to see channels you follow.")

    private var cancellables = Set<AnyCancellable>()
    private var hasLoaded = false

    init(auth: AuthService = AuthService.shared, api: TwitchAPIProviding = TwitchAPIClient.shared) {
        self.auth = auth
        self.api = api
        super.init(nibName: nil, bundle: nil)
        title = "Following"
        tabBarItem = UITabBarItem(title: "Following", image: UIImage(systemName: "heart"), selectedImage: UIImage(systemName: "heart.fill"))
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
        bootstrap()
    }

    func scrollToTop() {
        guard collectionView.numberOfSections > 0 else { return }
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: true)
    }

    private func bootstrap() {
        Task { [weak self] in
            guard let self else { return }
            guard let user = await self.auth.currentUser() else {
                self.signInView.isHidden = false
                return
            }
            self.signInView.isHidden = true
            self.bind(userID: user.id)
            self.viewModel?.load()
        }
    }

    private func bind(userID: String) {
        let model = StreamListViewModel(kind: .followed(userID: userID), api: api)
        viewModel = model
        model.streamsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] streams in
                MainActor.assumeIsolated { self?.apply(streams) }
            }
            .store(in: &cancellables)
        model.loadingSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                MainActor.assumeIsolated { self?.handleLoading(loading) }
            }
            .store(in: &cancellables)
        model.errorSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                MainActor.assumeIsolated { self?.handleError(message) }
            }
            .store(in: &cancellables)
    }

    private func setUpCollectionView() {
        let layout = StreamListLayout.make()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
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
        let registration = UICollectionView.CellRegistration<StreamCell, LiveStream> { cell, _, stream in
            cell.configure(with: stream)
        }
        dataSource = UICollectionViewDiffableDataSource<Int, LiveStream>(collectionView: collectionView) { collectionView, indexPath, stream in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: stream)
        }
    }

    private func setUpStates() {
        for state in [emptyView, signInView] {
            state.translatesAutoresizingMaskIntoConstraints = false
            state.isHidden = true
            view.addSubview(state)
            NSLayoutConstraint.activate([
                state.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                state.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                state.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
                state.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
            ])
        }
    }

    private func apply(_ streams: [LiveStream]) {
        hasLoaded = true
        var snapshot = NSDiffableDataSourceSnapshot<Int, LiveStream>()
        snapshot.appendSections([0])
        snapshot.appendItems(streams, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: true)
        emptyView.isHidden = !streams.isEmpty
    }

    private func handleLoading(_ loading: Bool) {
        if !loading { refreshControl.endRefreshing() }
        if loading, !hasLoaded { emptyView.isHidden = true }
    }

    private func handleError(_ message: String) {
        refreshControl.endRefreshing()
        emptyView.isHidden = (viewModel?.currentStreams.isEmpty == false)
    }

    @objc private func refresh() {
        viewModel?.load()
    }
}

extension FollowingViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let stream = dataSource.itemIdentifier(for: indexPath) else { return }
        navigationController?.pushViewController(ChannelViewController(channel: StreamRouting.channel(from: stream)), animated: true)
    }
}

extension FollowingViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard let max = indexPaths.map(\.item).max() else { return }
        let count = dataSource.snapshot().numberOfItems(inSection: 0)
        if max >= count - 6 {
            viewModel?.loadMore()
        }
    }
}
