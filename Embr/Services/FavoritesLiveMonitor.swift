import UIKit
import Combine
import EmbrCore

/// Which favorites are live right now, plus their avatars. Owned outside the Favorites screen
/// so the tab's live-count badge is current before that tab has ever been opened.
@MainActor
final class FavoritesLiveMonitor {
    static let shared = FavoritesLiveMonitor()

    enum Status: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let changes = PassthroughSubject<Void, Never>()

    private(set) var liveStreams: [LiveStream] = []
    private(set) var avatars: [String: URL] = [:]
    private(set) var status: Status = .idle

    private let favorites: FavoritesStore
    private let api: TwitchAPIProviding
    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var lastRefreshAt: Date?
    private var knownIDs: Set<String> = []
    private var started = false
    private static let minimumRefreshInterval: TimeInterval = 60
    private static let helixBatch = 100

    init(favorites: FavoritesStore = .shared, api: TwitchAPIProviding = TwitchAPIClient.shared) {
        self.favorites = favorites
        self.api = api
    }

    var liveCount: Int { liveStreams.count }

    func start() {
        guard !started else { return }
        started = true
        favorites.changes
            .sink { [weak self] channels in
                MainActor.assumeIsolated { self?.favoritesChanged(channels) }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(force: false) }
            }
            .store(in: &cancellables)
        Task { [weak self] in
            await self?.favorites.load()
            guard let self, self.lastRefreshAt == nil, self.status != .loading else { return }
            self.refresh(force: true)
        }
    }

    func refresh(force: Bool) {
        let channels = favorites.channels
        knownIDs = Set(channels.map(\.id))
        guard !channels.isEmpty else {
            refreshTask?.cancel()
            liveStreams = []
            status = .loaded
            changes.send()
            return
        }
        if !force, let last = lastRefreshAt, Date().timeIntervalSince(last) < Self.minimumRefreshInterval { return }
        refreshTask?.cancel()
        if status != .loaded { status = .loading }
        changes.send()
        let ids = channels.map(\.id)
        let missingAvatars = ids.filter { avatars[$0] == nil }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let streams = try await self.liveStreams(for: ids)
                let found = await self.avatarURLs(for: missingAvatars)
                guard !Task.isCancelled else { return }
                self.avatars.merge(found) { _, new in new }
                self.liveStreams = streams
                    .filter { self.knownIDs.contains($0.userID) }
                    .sorted { $0.viewerCount > $1.viewerCount }
                self.lastRefreshAt = Date()
                self.status = .loaded
            } catch {
                guard !Task.isCancelled else { return }
                AppLogger.shared.warn("favorites live refresh failed: \(error)", category: .api)
                if self.status != .loaded {
                    self.status = .failed(String(localized: "Couldn't check which favorites are live."))
                }
            }
            self.changes.send()
        }
    }

    /// A removal is answered locally so the channel disappears at once; an addition needs the
    /// network to learn whether the new favorite is live.
    private func favoritesChanged(_ channels: [FavoriteChannel]) {
        let ids = Set(channels.map(\.id))
        let added = !ids.subtracting(knownIDs).isEmpty
        knownIDs = ids
        liveStreams.removeAll { !ids.contains($0.userID) }
        if added {
            refresh(force: true)
        } else {
            changes.send()
        }
    }

    private func liveStreams(for ids: [String]) async throws -> [LiveStream] {
        var streams: [LiveStream] = []
        for start in stride(from: 0, to: ids.count, by: Self.helixBatch) {
            let batch = Array(ids[start..<min(start + Self.helixBatch, ids.count)])
            streams += try await api.streams(userIDs: batch)
        }
        return streams
    }

    private func avatarURLs(for ids: [String]) async -> [String: URL] {
        var found: [String: URL] = [:]
        for start in stride(from: 0, to: ids.count, by: Self.helixBatch) {
            let batch = Array(ids[start..<min(start + Self.helixBatch, ids.count)])
            guard let users = try? await api.users(ids: batch) else { continue }
            for user in users {
                if let url = user.profileImageURL { found[user.id] = url }
            }
        }
        return found
    }
}
