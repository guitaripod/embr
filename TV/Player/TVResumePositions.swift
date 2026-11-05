import Foundation

/// Where each past broadcast was left, so it picks up there next time. Kept in defaults, the one store tvOS keeps,
/// and limited to the most recent broadcasts so it stays within tvOS's small allowance.
enum TVResumePositions {
    private static let key = "tv.resumePositions.v1"
    private static let limit = 50
    private static let margin: TimeInterval = 60

    private struct Entry: Codable {
        let id: String
        let seconds: TimeInterval
        let savedAt: Date
    }

    /// The saved position, unless it is within a minute of either end.
    static func position(for videoID: String, duration: TimeInterval) -> TimeInterval? {
        guard let entry = entries().first(where: { $0.id == videoID }) else { return nil }
        guard entry.seconds > margin, duration <= 0 || entry.seconds < duration - margin else { return nil }
        return entry.seconds
    }

    /// Saves at most every ten seconds of playback, to keep defaults writes rare.
    static func save(_ seconds: TimeInterval, duration: TimeInterval, for videoID: String) {
        var all = entries()
        if let existing = all.first(where: { $0.id == videoID }), abs(existing.seconds - seconds) < 10 { return }
        all.removeAll { $0.id == videoID }
        all.insert(Entry(id: videoID, seconds: seconds, savedAt: Date()), at: 0)
        if let data = try? JSONEncoder().encode(Array(all.prefix(limit))) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func entries() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }
}
