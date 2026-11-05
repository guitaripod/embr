import UIKit
import EmbrCore
import MidgarCore

/// The biggest live streams and categories on Twitch right now, for anyone, signed in or not.
final class TVBrowseViewController: TVShelfViewController {
    private let api = AppContainer.shared.api

    override func load() async {
        let firstLoad = collectionView.numberOfSections == 0
        if firstLoad { stateView.showLoading() }
        async let streams = try? api.topStreams(after: nil, first: 40)
        async let categories = try? api.topCategories(after: nil, first: 40)
        let top = await streams?.items ?? []
        let games = await categories?.items ?? []
        guard !top.isEmpty || !games.isEmpty else {
            if firstLoad {
                stateView.show(
                    symbol: "wifi.exclamationmark",
                    title: String(localized: "Twitch can't be reached"),
                    message: String(localized: "Check the Apple TV's network connection."),
                    buttonTitle: String(localized: "Try Again")
                ) { [weak self] in self?.reload() }
            }
            return
        }
        apply([
            TVShelf(id: "top", title: String(localized: "Top Live"), style: .featured, items: top.prefix(6).map(TVShelfItem.stream)),
            TVShelf(id: "more", title: String(localized: "More Live Channels"), style: .streams, items: top.dropFirst(6).map(TVShelfItem.stream)),
            TVShelf(id: "categories", title: String(localized: "Top Categories"), style: .categories, items: games.map(TVShelfItem.category)),
        ])
    }
}

/// Every live stream in one category, in a grid that loads more as focus nears the end.
final class TVCategoryViewController: TVShelfViewController {
    private let category: GameCategory
    private let api = AppContainer.shared.api
    private var streams: [LiveStream] = []
    private var cursor: String?
    private var loadingMore = false

    init(category: GameCategory) {
        self.category = category
        super.init(nibName: nil, bundle: nil)
        title = category.name
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func load() async {
        if streams.isEmpty { stateView.showLoading() }
        guard let page = try? await api.streams(gameID: category.id, after: nil, first: 40) else {
            stateView.show(
                symbol: "wifi.exclamationmark",
                title: String(localized: "Twitch can't be reached"),
                message: nil,
                buttonTitle: String(localized: "Try Again")
            ) { [weak self] in self?.reload() }
            return
        }
        streams = page.items
        cursor = page.cursor
        render()
        if streams.isEmpty {
            stateView.show(symbol: "tv", title: String(localized: "Nobody is live in \(category.name)"), message: nil)
        }
    }

    private func render() {
        apply([TVShelf(id: "streams", title: category.name, style: .streamGrid, items: streams.map(TVShelfItem.stream))])
    }

    private func loadMore() {
        guard !loadingMore, let cursor else { return }
        loadingMore = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.loadingMore = false }
            guard let page = try? await self.api.streams(gameID: self.category.id, after: cursor, first: 40) else { return }
            let known = Set(self.streams.map(\.userID))
            self.streams.append(contentsOf: page.items.filter { !known.contains($0.userID) })
            self.cursor = page.cursor
            self.render()
        }
    }

    override func willShowItem(at indexPath: IndexPath) {
        if indexPath.item >= streams.count - 8 {
            loadMore()
        }
    }
}
