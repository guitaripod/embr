import UIKit
import Combine
import TVServices
import EmbrCore
import MidgarCore

/// Who is live among the person's favorites and followed channels, refreshed for the whole app at once: the Following
/// and Favorites tabs, the channel switcher in the player, the multiview picker and the Top Shelf all read it. Every
/// refresh also leaves a snapshot for the Top Shelf extension and asks the system to redraw the shelf.
@MainActor
final class TVLiveDirectory {
    static let shared = TVLiveDirectory()

    let changes = PassthroughSubject<Void, Never>()

    private(set) var favoritesLive: [LiveStream] = []
    private(set) var followedLive: [LiveStream] = []
    private(set) var followed: [FollowedChannel] = []
    private(set) var isSignedIn = false
    private(set) var lastRefresh: Date?
    private var avatars: [String: URL] = [:]
    private var refreshTask: Task<Void, Never>?

    private let api: TwitchAPIProviding
    private let auth: AuthService

    private static let followedLimit = 300

    init(api: TwitchAPIProviding = AppContainer.shared.api, auth: AuthService = AppContainer.shared.auth) {
        self.api = api
        self.auth = auth
    }

    /// Favorites first, then the followed channels, each by viewer count and each channel once.
    var liveNow: [LiveStream] {
        ShelfPlanner.entries(live: favoritesLive + followedLive, favoriteIDs: Set(FavoritesStore.shared.channels.map(\.id)), limit: 100)
            .map(\.stream)
    }

    func avatar(for userID: String) -> URL? {
        avatars[userID]
    }

    func refreshIfStale(maximumAge: TimeInterval = 60) async {
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < maximumAge { return }
        await refresh()
    }

    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// Reads the user records of `ids` the directory has no avatar for yet, in batches of 100.
    func loadAvatars(for ids: [String]) async {
        let missing = Array(Set(ids.filter { avatars[$0] == nil }))
        guard !missing.isEmpty else { return }
        for start in stride(from: 0, to: missing.count, by: 100) {
            let batch = Array(missing[start..<min(start + 100, missing.count)])
            guard let users = try? await api.users(ids: batch) else { continue }
            for user in users {
                avatars[user.id] = user.profileImageURL
            }
        }
    }

    private func performRefresh() async {
        await FavoritesStore.shared.load()
        let favorites = FavoritesStore.shared.channels
        let user = await auth.currentUser()
        isSignedIn = user != nil
        async let favoriteStreams = liveStreams(ids: favorites.map(\.id))
        async let followedStreams = followedLiveStreams(userID: user?.id)
        async let followedChannels = followedChannels(userID: user?.id)
        favoritesLive = await favoriteStreams
        followedLive = await followedStreams
        followed = await followedChannels
        lastRefresh = Date()
        await loadAvatars(for: (favoritesLive + followedLive).map(\.userID))
        writeTopShelfSnapshot(favorites: favorites)
        changes.send()
    }

    private func liveStreams(ids: [String]) async -> [LiveStream] {
        var result: [LiveStream] = []
        for start in stride(from: 0, to: ids.count, by: 100) {
            let batch = Array(ids[start..<min(start + 100, ids.count)])
            if let streams = try? await api.streams(userIDs: batch) {
                result.append(contentsOf: streams)
            }
        }
        return result.sorted { $0.viewerCount > $1.viewerCount }
    }

    private func followedLiveStreams(userID: String?) async -> [LiveStream] {
        guard let userID else { return [] }
        do {
            return try await api.followedStreams(userID: userID, after: nil, first: 100).items
        } catch {
            MidgarLog.notice("tv: followed streams failed: \(error)", category: .api)
            return followedLive
        }
    }

    private func followedChannels(userID: String?) async -> [FollowedChannel] {
        guard let userID else { return [] }
        var channels: [FollowedChannel] = []
        var cursor: String?
        repeat {
            guard let page = try? await api.followedChannels(userID: userID, after: cursor, first: 100) else { break }
            channels.append(contentsOf: page.items)
            cursor = page.cursor
        } while cursor != nil && channels.count < Self.followedLimit
        return channels.isEmpty ? followed : channels
    }

    private func writeTopShelfSnapshot(favorites: [FavoriteChannel]) {
        let snapshot = TopShelfSnapshot(
            favoriteIDs: favorites.map(\.id),
            followedIDs: followed.map(\.id),
            live: liveNow.prefix(ShelfPlanner.limit).map(TopShelfSnapshot.Stream.init),
            updatedAt: Date(),
            previews: SettingsStore.shared.current.livePreviewsEnabled
        )
        guard TopShelfSnapshotStore.save(snapshot) else {
            MidgarLog.notice("tv: top shelf snapshot not saved", category: .app)
            return
        }
        TVTopShelfContentProvider.topShelfContentDidChange()
    }
}
