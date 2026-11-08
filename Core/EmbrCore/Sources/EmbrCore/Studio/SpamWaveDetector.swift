import Foundation

/// Notices the shape of a bot or hate raid: the same long message posted by many different accounts within a minute.
/// It only ever suggests Shield Mode to the streamer, at most once every five minutes; it never acts.
public struct SpamWaveDetector: Sendable {
    public static let window: TimeInterval = 60
    public static let minimumRepeats = 12
    public static let minimumChatters = 8
    public static let minimumLength = 12
    public static let quietPeriod: TimeInterval = 5 * 60

    private struct Entry: Sendable {
        let at: Date
        let text: String
        let user: String
    }

    private var entries: [Entry] = []
    private var lastWarning: Date?

    public init() {}

    /// Takes one chat message in and returns true when it completes a wave worth warning about.
    public mutating func ingest(text: String, user: String, at now: Date) -> Bool {
        entries.removeAll { now.timeIntervalSince($0.at) > Self.window }
        let normalized = Self.normalize(text)
        guard normalized.count >= Self.minimumLength else { return false }
        entries.append(Entry(at: now, text: normalized, user: user))
        if let lastWarning, now.timeIntervalSince(lastWarning) < Self.quietPeriod { return false }
        let same = entries.filter { $0.text == normalized }
        guard same.count >= Self.minimumRepeats, Set(same.map(\.user)).count >= Self.minimumChatters else { return false }
        lastWarning = now
        return true
    }

    static func normalize(_ text: String) -> String {
        let folded = text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        return String(String.UnicodeScalarView(folded))
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}
