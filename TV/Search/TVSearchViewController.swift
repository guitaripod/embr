import UIKit
import EmbrCore
import MidgarCore

/// The Search tab: the system keyboard, with dictation from the Siri Remote, recent searches as suggestions, and
/// results for channels (live ones first) and categories as the person types.
enum TVSearch {
    @MainActor
    static func makeTab() -> UIViewController {
        let results = TVSearchResultsViewController()
        let search = UISearchController(searchResultsController: results)
        search.searchResultsUpdater = results
        search.searchBar.placeholder = String(localized: "Channels and categories")
        search.obscuresBackgroundDuringPresentation = false
        results.searchController = search
        let container = UISearchContainerViewController(searchController: search)
        return UINavigationController(rootViewController: container)
    }
}

final class TVSearchResultsViewController: TVShelfViewController, UISearchResultsUpdating {
    weak var searchController: UISearchController?
    private var query = ""
    private var searchTask: Task<Void, Never>?
    private let api = AppContainer.shared.api

    override var refreshInterval: TimeInterval { 600 }

    override func viewDidLoad() {
        super.viewDidLoad()
        showSuggestions()
    }

    func updateSearchResults(for searchController: UISearchController) {
        let text = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != query else { return }
        query = text
        searchTask?.cancel()
        guard !text.isEmpty else {
            apply([])
            showSuggestions()
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.search(text)
        }
    }

    override func load() async {
        guard !query.isEmpty else { return }
        await search(query)
    }

    private func search(_ text: String) async {
        async let channels = try? api.searchChannels(query: text, liveOnly: false, after: nil, first: 30).items
        async let categories = try? api.searchCategories(query: text, after: nil, first: 20).items
        let foundChannels = await channels ?? []
        let foundCategories = await categories ?? []
        guard !Task.isCancelled, text == query else { return }
        let ordered = foundChannels.sorted { $0.isLive && !$1.isLive }
        let liveIDs = ordered.filter(\.isLive).map(\.id)
        let live = (try? await api.streams(userIDs: Array(liveIDs.prefix(100)))) ?? []
        await TVLiveDirectory.shared.loadAvatars(for: ordered.map(\.id))
        guard !Task.isCancelled, text == query else { return }
        let channelItems = ordered.map { channel in
            TVShelfItem.channel(TVChannelSummary(
                id: channel.id, login: channel.broadcasterLogin, name: channel.broadcasterName,
                avatarURL: TVLiveDirectory.shared.avatar(for: channel.id), isLive: channel.isLive
            ))
        }
        apply([
            TVShelf(id: "live", title: String(localized: "Live"), style: .streams, items: live.sorted { $0.viewerCount > $1.viewerCount }.map(TVShelfItem.stream)),
            TVShelf(id: "channels", title: String(localized: "Channels"), style: .channels, items: channelItems),
            TVShelf(id: "categories", title: String(localized: "Categories"), style: .categories, items: foundCategories.map(TVShelfItem.category)),
        ])
        if ordered.isEmpty && foundCategories.isEmpty {
            stateView.show(symbol: "magnifyingglass", title: String(localized: "No results for “\(text)”"), message: nil)
        } else {
            TVRecentSearches.add(text)
        }
    }

    private func showSuggestions() {
        searchController?.searchSuggestions = TVRecentSearches.all.map { UISearchSuggestionItem(localizedSuggestion: $0) }
    }
}

/// The last searches that found something, offered as suggestions under the keyboard.
enum TVRecentSearches {
    private static let key = "tv.recentSearches"
    private static let limit = 8

    static var all: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func add(_ text: String) {
        var recent = all.filter { $0.caseInsensitiveCompare(text) != .orderedSame }
        recent.insert(text, at: 0)
        UserDefaults.standard.set(Array(recent.prefix(limit)), forKey: key)
    }
}
