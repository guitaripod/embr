import Foundation
import Combine
import EmbrCore

struct FavoriteChannel: Sendable, Hashable, Identifiable {
    let id: String
    let login: String
    let name: String
    let addedAt: Date

    var displayName: String { name.isEmpty ? login : name }
}

/// The channels a person starred in Embr, kept on this device and independent of any Twitch
/// account: they work logged out, and they survive logging in and out.
@MainActor
final class FavoritesStore {
    static let shared = FavoritesStore()

    let changes = PassthroughSubject<[FavoriteChannel], Never>()

    private(set) var channels: [FavoriteChannel] = []
    private(set) var isLoaded = false
    private var ids: Set<String> = []
    private let database: DatabaseManager

    init(database: DatabaseManager = .shared) {
        self.database = database
    }

    func load() async {
        guard !isLoaded else { return }
        let stored = await database.favoriteChannels().map(Self.channel(from:))
        let storedIDs = Set(stored.map(\.id))
        let starredWhileLoading = channels.filter { !storedIDs.contains($0.id) }
        isLoaded = true
        apply(starredWhileLoading + stored)
    }

    func isFavorite(_ id: String) -> Bool {
        ids.contains(id)
    }

    @discardableResult
    func toggle(id: String, login: String, name: String) -> Bool {
        if isFavorite(id) {
            remove(id: id)
            return false
        }
        add(id: id, login: login, name: name)
        return true
    }

    func add(id: String, login: String, name: String) {
        guard !id.isEmpty, !login.isEmpty, !isFavorite(id) else { return }
        let channel = FavoriteChannel(id: id, login: login, name: name, addedAt: Date())
        apply([channel] + channels)
        let record = JoinedChannelRecord(broadcasterID: id, login: login, displayName: name, addedAt: channel.addedAt)
        Task { await database.addFavoriteChannel(record) }
        AppLogger.shared.info("favorited \(login)", category: .persistence)
    }

    func remove(id: String) {
        guard isFavorite(id) else { return }
        apply(channels.filter { $0.id != id })
        Task { await database.removeFavoriteChannel(broadcasterID: id) }
        AppLogger.shared.info("unfavorited \(id)", category: .persistence)
    }

    #if DEBUG
    /// Poses the Favorites tab for screenshots without writing to the device's real list.
    func seedForScreenshots(_ seeded: [FavoriteChannel]) {
        isLoaded = true
        apply(seeded)
    }
    #endif

    private func apply(_ next: [FavoriteChannel]) {
        channels = next
        ids = Set(next.map(\.id))
        changes.send(next)
    }

    private static func channel(from record: JoinedChannelRecord) -> FavoriteChannel {
        FavoriteChannel(id: record.broadcasterID, login: record.login, name: record.displayName, addedAt: record.addedAt)
    }
}
