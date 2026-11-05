import Foundation
import Combine
import EmbrCore
import MidgarCore

/// Keeps the starred channels the same on every device of the person's Apple Account through iCloud key-value
/// storage: a star on the iPhone shows on the Apple TV. Each device keeps a ``FavoritesLedger`` of adds and removals
/// with their times, merges it with the one in iCloud and applies the result to ``FavoritesStore``. Without iCloud
/// the ledger stays on the device and nothing else changes.
@MainActor
final class FavoritesSync {
    static let shared = FavoritesSync()

    private let favorites: FavoritesStore
    private let cloud: NSUbiquitousKeyValueStore
    private let defaults: UserDefaults
    private var ledger: FavoritesLedger
    private var applied: [FavoriteChannel] = []
    private var applyingMerge = false
    private var started = false
    private var cancellables = Set<AnyCancellable>()

    private static let cloudKey = "favorites.ledger.v1"
    private static let localKey = "favorites.ledger.v1"

    init(favorites: FavoritesStore = .shared, cloud: NSUbiquitousKeyValueStore = .default, defaults: UserDefaults = .standard) {
        self.favorites = favorites
        self.cloud = cloud
        self.defaults = defaults
        ledger = Self.decode(defaults.data(forKey: Self.localKey)) ?? FavoritesLedger()
    }

    /// Starts syncing. A test host or a demo capture keeps its invented favorites out of iCloud.
    func start() {
        guard !started, EmbrMidgar.reachesMidgarServices else { return }
        started = true
        Task { [weak self] in
            guard let self else { return }
            await self.favorites.load()
            self.adoptLocalFavorites()
            self.mergeCloud()
            self.favorites.changes
                .sink { [weak self] channels in self?.recordLocalChange(channels) }
                .store(in: &self.cancellables)
            NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: self.cloud)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.mergeCloud() }
                .store(in: &self.cancellables)
            self.cloud.synchronize()
        }
    }

    /// Records the stars that exist on this device but never reached the ledger: the ones made before sync existed, or
    /// the ones a restored database brought back.
    private func adoptLocalFavorites() {
        for channel in favorites.channels where ledger.favorites[channel.id] == nil {
            ledger.add(SyncedFavorite(id: channel.id, login: channel.login, name: channel.name, addedAt: channel.addedAt))
        }
        applied = favorites.channels
    }

    private func recordLocalChange(_ channels: [FavoriteChannel]) {
        guard !applyingMerge else {
            applied = channels
            return
        }
        let previous = Set(applied.map(\.id))
        let current = Set(channels.map(\.id))
        let now = Date()
        for channel in channels where !previous.contains(channel.id) {
            ledger.add(SyncedFavorite(id: channel.id, login: channel.login, name: channel.name, addedAt: channel.addedAt))
        }
        for id in previous.subtracting(current) {
            ledger.remove(id: id, at: now)
        }
        applied = channels
        persist(pushing: true)
    }

    private func mergeCloud() {
        let remote = Self.decode(cloud.data(forKey: Self.cloudKey))
        let merged = (remote.map { ledger.merged(with: $0) } ?? ledger).pruned(now: Date())
        ledger = merged
        apply(merged)
        persist(pushing: remote != merged)
    }

    /// Brings ``FavoritesStore`` in line with the ledger without recording the changes as new local edits.
    private func apply(_ ledger: FavoritesLedger) {
        let wanted = Dictionary(uniqueKeysWithValues: ledger.active.map { ($0.id, $0) })
        let present = Set(favorites.channels.map(\.id))
        applyingMerge = true
        for (id, favorite) in wanted where !present.contains(id) {
            favorites.add(id: favorite.id, login: favorite.login, name: favorite.name, addedAt: favorite.addedAt)
        }
        for id in present where wanted[id] == nil {
            favorites.remove(id: id)
        }
        applyingMerge = false
        applied = favorites.channels
        let changes = wanted.count - present.intersection(wanted.keys).count + present.subtracting(wanted.keys).count
        if changes > 0 {
            MidgarLog.info("favorites sync: applied \(changes) changes from iCloud", category: .persistence)
        }
    }

    private func persist(pushing: Bool) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: Self.localKey)
        guard pushing else { return }
        cloud.set(data, forKey: Self.cloudKey)
    }

    private static func decode(_ data: Data?) -> FavoritesLedger? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(FavoritesLedger.self, from: data)
    }
}
