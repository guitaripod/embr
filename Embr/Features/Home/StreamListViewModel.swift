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
    private static let cardMinimumWidth: CGFloat = 280
    private static let cardSpacing: CGFloat = 20
    private static let regularMargin: CGFloat = 20

    /// iPad windows of regular width show streams as a grid of cards; compact widths (the
    /// phone, Slide Over, a narrow split) keep the thumbnail-beside-text rows.
    static func usesCards(_ traits: UITraitCollection) -> Bool {
        traits.userInterfaceIdiom != .phone && traits.horizontalSizeClass == .regular
    }

    static func make() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            MainActor.assumeIsolated {
                streamsSection(environment: environment)
            }
        }
    }

    static func streamsSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        if usesCards(environment.traitCollection) {
            return cardSection(environment: environment)
        }
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

    /// Cards at least 280 points wide, as many to a row as the window fits, aligned with the
    /// large title on the layout margins.
    static func cardSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let columns = max(2, columnCount(environment: environment, minimumWidth: cardMinimumWidth, spacing: cardSpacing))
        let section = grid(columns: columns, spacing: cardSpacing, estimatedHeight: 280)
        section.interGroupSpacing = 26
        section.contentInsets.top = 8
        section.contentInsets.bottom = 28
        return section
    }

    /// Equal columns with `spacing` between them, aligned to the layout margins. Fractional
    /// items have no gutter of their own, so each gives up half the spacing on either side and
    /// the section pulls its outer edges back out to the margins.
    private static func grid(columns: Int, spacing: CGFloat, estimatedHeight: CGFloat) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
            heightDimension: .estimated(estimatedHeight)
        ))
        item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: spacing / 2, bottom: 0, trailing: spacing / 2)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(estimatedHeight)),
            repeatingSubitem: item,
            count: columns
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsetsReference = .layoutMargins
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: -spacing / 2, bottom: 0, trailing: -spacing / 2)
        return section
    }

    /// Box art for categories: three across on the phone, as many as fit at 150 points or more
    /// on iPad.
    static func categoriesSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        guard usesCards(environment.traitCollection) else {
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / 3.0),
                heightDimension: .fractionalHeight(1.0)
            ))
            item.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(210)),
                repeatingSubitem: item,
                count: 3
            )
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 9, bottom: 8, trailing: 9)
            return section
        }
        let spacing: CGFloat = 16
        let columns = max(4, columnCount(environment: environment, minimumWidth: 150, spacing: spacing))
        let section = grid(columns: columns, spacing: spacing, estimatedHeight: 260)
        section.interGroupSpacing = 18
        section.contentInsets.top = 8
        section.contentInsets.bottom = 24
        return section
    }

    static func categoriesLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            MainActor.assumeIsolated {
                categoriesSection(environment: environment)
            }
        }
    }

    /// Channel rows (offline follows and favorites, search results): one list on the phone,
    /// side-by-side columns at least 300 points wide on iPad.
    static func channelRowsSection(environment: NSCollectionLayoutEnvironment, estimatedHeight: CGFloat) -> NSCollectionLayoutSection {
        guard usesCards(environment.traitCollection) else {
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(estimatedHeight)))
            let group = NSCollectionLayoutGroup.vertical(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(estimatedHeight)),
                subitems: [item])
            return NSCollectionLayoutSection(group: group)
        }
        let spacing: CGFloat = 24
        let columns = max(1, columnCount(environment: environment, minimumWidth: 300, spacing: spacing))
        let section = grid(columns: columns, spacing: spacing, estimatedHeight: estimatedHeight)
        section.interGroupSpacing = 4
        return section
    }

    /// An inset-grouped list (Settings and its sub-screens) that keeps to a readable width on
    /// iPad instead of stretching its rows across a wide window.
    static func readableList(using configuration: UICollectionLayoutListConfiguration) -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            MainActor.assumeIsolated {
                let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
                if environment.traitCollection.userInterfaceIdiom != .phone {
                    section.contentInsetsReference = .readableContent
                }
                return section
            }
        }
    }

    /// Headers follow the section's content insets, so a grid's negative gutter insets are
    /// handed back to the header and its title lines up with the first column.
    static func attachHeader(_ header: NSCollectionLayoutBoundarySupplementaryItem, to section: NSCollectionLayoutSection) {
        header.contentInsets = NSDirectionalEdgeInsets(
            top: 0, leading: -section.contentInsets.leading, bottom: 0, trailing: -section.contentInsets.trailing)
        section.boundarySupplementaryItems = [header]
    }

    /// How many items of at least `minimumWidth` fit across the content, which on iPad sits
    /// inside 20-point layout margins.
    static func columnCount(environment: NSCollectionLayoutEnvironment, minimumWidth: CGFloat, spacing: CGFloat) -> Int {
        let width = environment.container.effectiveContentSize.width - 2 * regularMargin
        return max(1, Int((width + spacing) / (minimumWidth + spacing)))
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
