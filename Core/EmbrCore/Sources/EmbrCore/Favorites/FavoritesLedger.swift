import Foundation

/// A starred channel as it travels between a person's devices.
public struct SyncedFavorite: Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let login: String
    public let name: String
    public let addedAt: Date

    public init(id: String, login: String, name: String, addedAt: Date) {
        self.id = id
        self.login = login
        self.name = name
        self.addedAt = addedAt
    }
}

/// Every device's view of the starred channels, kept in iCloud key-value storage so a star on the iPhone shows on
/// the Apple TV. Adds and removals both carry the time they happened and the later one wins per channel, so two
/// devices that changed the list while apart agree after one merge whichever merges first.
public struct FavoritesLedger: Codable, Sendable, Equatable {
    public private(set) var favorites: [String: SyncedFavorite]
    public private(set) var removals: [String: Date]

    /// How long a removal is remembered. A device offline for longer than this could bring a removed star back.
    public static let removalMemory: TimeInterval = 180 * 86_400

    public init(favorites: [SyncedFavorite] = [], removals: [String: Date] = [:]) {
        self.favorites = Dictionary(favorites.map { ($0.id, $0) }, uniquingKeysWith: { $0.addedAt >= $1.addedAt ? $0 : $1 })
        self.removals = removals
        dropSuperseded()
    }

    /// The starred channels, newest first.
    public var active: [SyncedFavorite] {
        favorites.values.sorted { lhs, rhs in
            lhs.addedAt == rhs.addedAt ? lhs.id < rhs.id : lhs.addedAt > rhs.addedAt
        }
    }

    public mutating func add(_ favorite: SyncedFavorite) {
        if let removed = removals[favorite.id], removed >= favorite.addedAt { return }
        if let existing = favorites[favorite.id], existing.addedAt >= favorite.addedAt { return }
        favorites[favorite.id] = favorite
        removals.removeValue(forKey: favorite.id)
    }

    public mutating func remove(id: String, at date: Date) {
        if let existing = favorites[id], existing.addedAt > date { return }
        favorites.removeValue(forKey: id)
        removals[id] = max(date, removals[id] ?? date)
    }

    /// The ledger both sides agree on: the later of an add and a removal wins for every channel.
    public func merged(with other: FavoritesLedger) -> FavoritesLedger {
        var result = self
        for (id, date) in other.removals {
            result.removals[id] = max(date, result.removals[id] ?? date)
        }
        for favorite in other.favorites.values {
            if let existing = result.favorites[favorite.id], existing.addedAt >= favorite.addedAt { continue }
            result.favorites[favorite.id] = favorite
        }
        result.dropSuperseded()
        return result
    }

    /// Forgets removals older than ``removalMemory``, so the ledger stays small.
    public func pruned(now: Date) -> FavoritesLedger {
        var result = self
        result.removals = removals.filter { now.timeIntervalSince($0.value) < Self.removalMemory }
        return result
    }

    private mutating func dropSuperseded() {
        for (id, removedAt) in removals {
            guard let favorite = favorites[id] else { continue }
            if favorite.addedAt > removedAt {
                removals.removeValue(forKey: id)
            } else {
                favorites.removeValue(forKey: id)
            }
        }
    }
}
