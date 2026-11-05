import Foundation

/// Picks the live channels the Apple TV Top Shelf shows: the person's favorites first, then the channels they follow,
/// each group by viewer count, one entry per channel.
public enum ShelfPlanner {
    public static let limit = 10

    public struct Entry: Sendable, Equatable {
        public let stream: LiveStream
        public let isFavorite: Bool

        public init(stream: LiveStream, isFavorite: Bool) {
            self.stream = stream
            self.isFavorite = isFavorite
        }
    }

    public static func entries(live streams: [LiveStream], favoriteIDs: Set<String>, limit: Int = limit) -> [Entry] {
        var seen: Set<String> = []
        let unique = streams.filter { seen.insert($0.userID).inserted }
        let ranked = unique.sorted { lhs, rhs in
            let lhsFavorite = favoriteIDs.contains(lhs.userID)
            let rhsFavorite = favoriteIDs.contains(rhs.userID)
            if lhsFavorite != rhsFavorite { return lhsFavorite }
            if lhs.viewerCount != rhs.viewerCount { return lhs.viewerCount > rhs.viewerCount }
            return lhs.userLogin < rhs.userLogin
        }
        return ranked.prefix(max(0, limit)).map { Entry(stream: $0, isFavorite: favoriteIDs.contains($0.userID)) }
    }
}
