import UIKit
import Combine
import EmbrCore

@MainActor
final class FollowingViewController: UIViewController {
    private enum Section: Hashable { case live, offline }
    private enum Item: Hashable {
        case stream(LiveStream)
        case channel(FollowedChannel)
    }

    private let auth: AuthService
    private let api: TwitchAPIProviding

    private var viewModel: StreamListViewModel?
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private let refreshControl = UIRefreshControl()
    private let emptyView = EmptyStateView(symbol: "heart.slash", message: String(localized: "You don't follow any channels yet."))
    private let signInView = EmptyStateView(symbol: "person.crop.circle.badge.exclamationmark", message: String(localized: "Sign in to see channels you follow."))
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.color = Theme.secondaryText
        return indicator
    }()
    private static var emptyMessage: String { String(localized: "You don't follow any channels yet.") }

    private var liveStreams: [LiveStream] = []
    private var followedChannels: [FollowedChannel] = []
    private var avatars: [String: URL] = [:]
    private var userID: String?
    private var channelsTask: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()
    private var hasLoaded = false
    private var streamsLoaded = false
    private var channelsLoaded = false

    init(auth: AuthService = AuthService.shared, api: TwitchAPIProviding = TwitchAPIClient.shared) {
        self.auth = auth
        self.api = api
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Following")
        tabBarItem = UITabBarItem(title: String(localized: "Following"), image: UIImage(systemName: "heart"), selectedImage: UIImage(systemName: "heart.fill"))
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
        setUpSignInAction()
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (controller: FollowingViewController, _) in
            controller.reloadForWidthClass()
        }
        bootstrap()
    }

    private var usesCards: Bool { StreamListLayout.usesCards(traitCollection) }

    /// Crossing between compact and regular width swaps rows for cards, so every cell is
    /// dequeued again from the other registration.
    private func reloadForWidthClass() {
        var snapshot = dataSource.snapshot()
        guard !snapshot.sectionIdentifiers.isEmpty else { return }
        snapshot.reloadSections(snapshot.sectionIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func scrollToTop() {
        guard collectionView.numberOfSections > 0 else { return }
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: true)
    }

    private func bootstrap() {
        #if DEBUG
        if ScreenshotHarness.seededFollow {
            loadScreenshotFollows()
            return
        }
        #endif
        loadingIndicator.startAnimating()
        Task { [weak self] in
            guard let self else { return }
            guard let user = await self.auth.currentUser() else {
                self.loadingIndicator.stopAnimating()
                self.signInView.isHidden = false
                return
            }
            self.signInView.isHidden = true
            self.userID = user.id
            self.bind(userID: user.id)
            self.viewModel?.load()
            self.loadFollowedChannels()
        }
    }

    #if DEBUG
    private func loadScreenshotFollows() {
        signInView.isHidden = true
        loadingIndicator.startAnimating()
        channelsLoaded = true
        Task { [weak self] in
            guard let self else { return }
            var ids: [String] = []
            for login in ScreenshotHarness.curatedFollowLogins {
                if let user = try? await self.api.user(login: login) { ids.append(user.id) }
            }
            let streams = (try? await self.api.streams(userIDs: ids)) ?? []
            let ordered = ids.compactMap { id in streams.first { $0.userID == id } }
            self.applyLive(ordered)
        }
    }
    #endif

    private func bind(userID: String) {
        let model = StreamListViewModel(kind: .followed(userID: userID), api: api)
        viewModel = model
        model.streamsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] streams in
                MainActor.assumeIsolated { self?.applyLive(streams) }
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
        model.avatarsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.reconfigureLiveAvatars() }
            }
            .store(in: &cancellables)
    }

    private func reconfigureLiveAvatars() {
        var snapshot = dataSource.snapshot()
        guard snapshot.sectionIdentifiers.contains(.live) else { return }
        snapshot.reconfigureItems(snapshot.itemIdentifiers(inSection: .live))
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func loadFollowedChannels() {
        guard let userID else { return }
        channelsTask?.cancel()
        channelsTask = Task { [weak self] in
            guard let self else { return }
            var collected: [FollowedChannel] = []
            var cursor: String?
            var pages = 0
            repeat {
                guard let page = try? await self.api.followedChannels(userID: userID, after: cursor, first: 100) else { break }
                collected.append(contentsOf: page.items)
                cursor = page.cursor
                pages += 1
            } while cursor != nil && pages < 3 && !Task.isCancelled
            if Task.isCancelled { return }
            self.followedChannels = collected
            self.channelsLoaded = true
            self.rebuild()
            self.loadAvatars()
        }
    }

    private func loadAvatars() {
        let liveIDs = Set(liveStreams.map(\.userID))
        let offlineIDs = followedChannels.map(\.id).filter { !liveIDs.contains($0) && avatars[$0] == nil }
        guard !offlineIDs.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            for chunk in stride(from: 0, to: offlineIDs.count, by: 100).map({ Array(offlineIDs[$0..<min($0 + 100, offlineIDs.count)]) }) {
                guard let users = try? await self.api.users(ids: chunk) else { continue }
                for user in users { if let url = user.profileImageURL { self.avatars[user.id] = url } }
                if Task.isCancelled { return }
                self.reconfigureOffline()
            }
        }
    }

    private func setUpCollectionView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.preservesSuperviewLayoutMargins = !OrientationCoordinator.isPhone
        collectionView.delegate = self
        collectionView.dragDelegate = self
        collectionView.prefetchDataSource = self
        collectionView.refreshControl = refreshControl
        refreshControl.tintColor = Theme.accent
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
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
                    return Self.offlineSection(environment: environment)
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
        let cards = StreamListLayout.usesCards(environment.traitCollection)
        section.contentInsets.top = 6
        section.contentInsets.bottom = cards ? 24 : 10
        StreamListLayout.attachHeader(headerItem(), to: section)
        return section
    }

    private static func offlineSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let section = StreamListLayout.channelRowsSection(environment: environment, estimatedHeight: 56)
        section.contentInsets.top = 4
        section.contentInsets.bottom = 16
        StreamListLayout.attachHeader(headerItem(), to: section)
        return section
    }

    private func setUpDataSource() {
        let streamRegistration = UICollectionView.CellRegistration<StreamCell, LiveStream> { [weak self] cell, _, stream in
            cell.configure(with: stream, avatarURL: self?.viewModel?.avatarURL(for: stream.userID))
        }
        let cardRegistration = UICollectionView.CellRegistration<StreamCardCell, LiveStream> { [weak self] cell, _, stream in
            cell.configure(with: stream, avatarURL: self?.viewModel?.avatarURL(for: stream.userID))
        }
        let channelRegistration = UICollectionView.CellRegistration<FollowedChannelCell, FollowedChannel> { [weak self] cell, _, channel in
            cell.alignsWithMargins = self?.usesCards ?? false
            cell.configure(with: channel, avatarURL: self?.avatars[channel.id])
        }
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .stream(let stream):
                if StreamListLayout.usesCards(collectionView.traitCollection) {
                    return collectionView.dequeueConfiguredReusableCell(using: cardRegistration, for: indexPath, item: stream)
                }
                return collectionView.dequeueConfiguredReusableCell(using: streamRegistration, for: indexPath, item: stream)
            case .channel(let channel):
                return collectionView.dequeueConfiguredReusableCell(using: channelRegistration, for: indexPath, item: channel)
            }
        }
        let headerRegistration = UICollectionView.SupplementaryRegistration<SectionHeaderView>(elementKind: SectionHeaderView.elementKind) { [weak self] view, _, indexPath in
            let section = self?.dataSource.sectionIdentifier(for: indexPath.section)
            view.configure(
                title: section == .offline ? String(localized: "Channels") : String(localized: "Live"),
                alignsWithMargins: self?.usesCards ?? false
            )
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: headerRegistration, for: indexPath)
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
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setUpSignInAction() {
        signInView.setAction(
            title: String(localized: "Connect Twitch"),
            footnote: String(localized: "No account? Star channels to keep them in Favorites.")
        ) { [weak self] in self?.connectTwitch() }
    }

    private func connectTwitch() {
        guard let anchor = view.window else {
            AppLogger.shared.warn("following login: no window anchor available", category: .auth)
            return
        }
        signInView.setActionEnabled(false)
        Task { [weak self] in
            guard let self else { return }
            do {
                let user = try await self.auth.login(presentationAnchor: anchor)
                AppLogger.shared.info("following login succeeded for \(user.login)", category: .auth)
                self.signInView.isHidden = true
                self.signInView.setActionEnabled(true)
                self.bootstrap()
                LiveAlertsPrompt.offerAfterSignIn(from: self)
            } catch APIError.cancelled {
                AppLogger.shared.info("following login cancelled by user", category: .auth)
                self.signInView.setActionEnabled(true)
            } catch {
                AppLogger.shared.warn("following login failed: \(error)", category: .auth)
                self.signInView.setActionEnabled(true)
                self.presentLoginError()
            }
        }
    }

    private func presentLoginError() {
        let alert = UIAlertController(
            title: String(localized: "Sign In Failed"),
            message: String(localized: "Could not connect your Twitch account. You can continue as a guest and sign in later."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }

    private func applyLive(_ streams: [LiveStream]) {
        liveStreams = streams
        streamsLoaded = true
        rebuild()
        loadAvatars()
    }

    private func rebuild() {
        let bothLoaded = streamsLoaded && channelsLoaded
        if bothLoaded {
            hasLoaded = true
            loadingIndicator.stopAnimating()
        }
        let liveIDs = Set(liveStreams.map(\.userID))
        let offline = followedChannels
            .filter { !liveIDs.contains($0.id) }
            .sorted { $0.broadcasterName.localizedCaseInsensitiveCompare($1.broadcasterName) == .orderedAscending }
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        if !liveStreams.isEmpty {
            snapshot.appendSections([.live])
            snapshot.appendItems(liveStreams.map(Item.stream), toSection: .live)
        }
        if !offline.isEmpty {
            snapshot.appendSections([.offline])
            snapshot.appendItems(offline.map(Item.channel), toSection: .offline)
        }
        dataSource.apply(snapshot, animatingDifferences: true)
        emptyView.setMessage(Self.emptyMessage)
        emptyView.onRetry = nil
        emptyView.isHidden = !(bothLoaded && liveStreams.isEmpty && offline.isEmpty)
    }

    private func reconfigureOffline() {
        var snapshot = dataSource.snapshot()
        guard snapshot.sectionIdentifiers.contains(.offline) else { return }
        snapshot.reconfigureItems(snapshot.itemIdentifiers(inSection: .offline))
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func handleLoading(_ loading: Bool) {
        if !loading { refreshControl.endRefreshing() }
        if loading, !hasLoaded { emptyView.isHidden = true }
    }

    private func handleError(_ message: String) {
        loadingIndicator.stopAnimating()
        refreshControl.endRefreshing()
        guard liveStreams.isEmpty, followedChannels.isEmpty else { return }
        emptyView.setMessage(message)
        emptyView.onRetry = { [weak self] in
            self?.viewModel?.load()
            self?.loadFollowedChannels()
        }
        emptyView.isHidden = false
    }

    @objc private func refresh() {
        Haptics.selection()
        viewModel?.load()
        loadFollowedChannels()
    }
}

extension FollowingViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        Haptics.selection()
        switch item {
        case .stream(let stream):
            navigationController?.pushViewController(ChannelViewController(channel: StreamRouting.channel(from: stream)), animated: true)
        case .channel(let channel):
            let info = ChannelInfo(id: channel.id, broadcasterLogin: channel.broadcasterLogin, broadcasterName: channel.broadcasterName, gameID: "", gameName: "", title: "", language: "")
            navigationController?.pushViewController(ChannelViewController(channel: info), animated: true)
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .stream(let stream):
            return ChannelActions.configuration(login: stream.userLogin, broadcasterID: stream.userID, name: stream.userName, from: self)
        case .channel(let channel):
            return ChannelActions.configuration(login: channel.broadcasterLogin, broadcasterID: channel.id, name: channel.broadcasterName, from: self)
        case .none:
            return nil
        }
    }
}

extension FollowingViewController: UICollectionViewDragDelegate {
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .stream(let stream):
            return ChannelActions.dragItems(login: stream.userLogin, name: stream.userName)
        case .channel(let channel):
            return ChannelActions.dragItems(login: channel.broadcasterLogin, name: channel.broadcasterName)
        case .none:
            return []
        }
    }
}

extension FollowingViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let liveItems = indexPaths.filter { dataSource.sectionIdentifier(for: $0.section) == .live }
        guard let max = liveItems.map(\.item).max() else { return }
        let count = liveStreams.count
        if max >= count - 6 {
            viewModel?.loadMore()
        }
    }
}
