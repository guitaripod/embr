import UIKit
import Combine
import EmbrCore

enum StreamRouting {
    static func channel(from stream: LiveStream) -> ChannelInfo {
        ChannelInfo(
            id: stream.userID,
            broadcasterLogin: stream.userLogin,
            broadcasterName: stream.userName,
            gameID: stream.gameID,
            gameName: stream.gameName,
            title: stream.title,
            language: stream.language,
            tags: stream.tags
        )
    }

    static func channel(from channel: WatchedChannel) -> ChannelInfo {
        ChannelInfo(
            id: channel.id,
            broadcasterLogin: channel.login,
            broadcasterName: channel.name,
            gameID: "",
            gameName: "",
            title: "",
            language: ""
        )
    }
}

@MainActor
enum StreamListLayout {
    static func make() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            MainActor.assumeIsolated {
                streamsSection(environment: environment)
            }
        }
    }

    static func streamsSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let columns = environment.container.effectiveContentSize.width > 700 ? 2 : 1
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
            heightDimension: .estimated(96)
        ))
        item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(96)),
            repeatingSubitem: item,
            count: columns
        )
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 14
        section.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0)
        return section
    }

    static func grid(columns: Int) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, _ in
            MainActor.assumeIsolated {
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                    heightDimension: .fractionalHeight(1.0)
                ))
                item.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5)
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(210)),
                    repeatingSubitem: item,
                    count: columns
                )
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 9, bottom: 8, trailing: 9)
                return section
            }
        }
    }
}

@MainActor
final class EmptyStateView: UIView {
    private let iconView = UIImageView()
    private let label = UILabel()
    private let retryButton = UIButton(type: .system)

    var onRetry: (() -> Void)? {
        didSet { retryButton.isHidden = onRetry == nil }
    }

    init(symbol: String, message: String) {
        super.init(frame: .zero)
        iconView.image = UIImage(systemName: symbol)
        iconView.tintColor = Theme.secondaryText
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .light)

        label.text = message
        label.font = .systemFont(ofSize: 15, weight: .regular)
        label.textColor = Theme.secondaryText
        label.textAlignment = .center
        label.numberOfLines = 0

        var configuration = UIButton.Configuration.tinted()
        configuration.title = String(localized: "Retry")
        configuration.cornerStyle = .large
        configuration.baseForegroundColor = Theme.accent
        retryButton.configuration = configuration
        retryButton.isHidden = true
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [iconView, label, retryButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        iconView.isAccessibilityElement = false
        isAccessibilityElement = true
        accessibilityLabel = message
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setMessage(_ message: String) {
        label.text = message
        accessibilityLabel = message
    }
}

@MainActor
final class StreamListViewModel {
    enum ListKind: Sendable, Equatable {
        case followed(userID: String)
        case top
        case game(id: String)
    }

    let streamsSubject = PassthroughSubject<[LiveStream], Never>()
    let loadingSubject = PassthroughSubject<Bool, Never>()
    let errorSubject = PassthroughSubject<String, Never>()
    let avatarsSubject = PassthroughSubject<Void, Never>()

    private let kind: ListKind
    private let api: TwitchAPIProviding
    private let pageSize: Int

    private var streams: [LiveStream] = []
    private var cursor: String?
    private var hasMore = true
    private var isLoading = false
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    private(set) var avatars: [String: URL] = [:]
    private var avatarTask: Task<Void, Never>?

    init(kind: ListKind, api: TwitchAPIProviding = TwitchAPIClient.shared, pageSize: Int = 25) {
        self.kind = kind
        self.api = api
        self.pageSize = pageSize
    }

    var currentStreams: [LiveStream] { streams }

    func avatarURL(for userID: String) -> URL? { avatars[userID] }

    private func fetchAvatars(for streams: [LiveStream], generation: Int) {
        let missing = streams.map(\.userID).filter { avatars[$0] == nil }
        guard !missing.isEmpty else { return }
        avatarTask?.cancel()
        avatarTask = Task { [weak self] in
            guard let self else { return }
            for start in stride(from: 0, to: missing.count, by: 100) {
                let chunk = Array(missing[start..<min(start + 100, missing.count)])
                guard let users = try? await self.api.users(ids: chunk) else { continue }
                guard !Task.isCancelled, generation == self.generation else { return }
                for user in users where user.profileImageURL != nil {
                    self.avatars[user.id] = user.profileImageURL
                }
                self.avatarsSubject.send(())
            }
        }
    }

    func load() {
        loadTask?.cancel()
        avatarTask?.cancel()
        generation += 1
        isLoading = false
        cursor = nil
        hasMore = true
        loadTask = Task { [weak self] in
            await self?.fetch(replacing: true, generation: self?.generation ?? 0)
        }
    }

    func loadMore() {
        guard hasMore, !isLoading, cursor != nil else { return }
        loadTask = Task { [weak self] in
            await self?.fetch(replacing: false, generation: self?.generation ?? 0)
        }
    }

    private func fetch(replacing: Bool, generation: Int) async {
        isLoading = true
        loadingSubject.send(true)
        defer {
            if generation == self.generation {
                isLoading = false
                loadingSubject.send(false)
                loadTask = nil
            }
        }
        do {
            let page = try await page(after: replacing ? nil : cursor)
            guard !Task.isCancelled, generation == self.generation else { return }
            cursor = page.cursor
            hasMore = page.cursor != nil
            if replacing {
                streams = page.items
            } else {
                let known = Set(streams.map(\.id))
                streams.append(contentsOf: page.items.filter { !known.contains($0.id) })
            }
            streamsSubject.send(streams)
            fetchAvatars(for: streams, generation: generation)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == self.generation else { return }
            AppLogger.shared.warn("Stream list load failed: \(error)", category: .api)
            errorSubject.send(describe(error))
        }
    }

    private func page(after: String?) async throws -> Page<LiveStream> {
        switch kind {
        case .followed(let userID):
            return try await api.followedStreams(userID: userID, after: after, first: pageSize)
        case .top:
            return try await api.topStreams(after: after, first: pageSize)
        case .game(let id):
            return try await api.streams(gameID: id, after: after, first: pageSize)
        }
    }

    private func describe(_ error: Error) -> String {
        guard let apiError = error as? APIError else { return String(localized: "Could not load streams") }
        switch apiError {
        case .unauthorized:
            if case .followed = kind { return String(localized: "Sign in to see this") }
            return String(localized: "Couldn't load streams — try again.")
        case .rateLimited: return String(localized: "Slow down — too many requests")
        case .network: return String(localized: "Network error")
        case .timeout: return String(localized: "Request timed out")
        default: return String(localized: "Could not load streams")
        }
    }
}
