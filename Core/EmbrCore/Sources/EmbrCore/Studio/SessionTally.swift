import Foundation

/// What happened during one stream, counted on the device for the recap. Counts only: no names and nothing per viewer,
/// and the recap is thrown away a day after the stream ended, inside Twitch's 24-hour limit on keeping its data.
public struct SessionTally: Sendable, Equatable, Codable {
    public static let keepFor: TimeInterval = 24 * 60 * 60

    public var startedAt: Date
    public var endedAt: Date?
    public var followers = 0
    public var subscriptions = 0
    public var giftedSubscriptions = 0
    public var bits = 0
    public var raids = 0
    public var raidViewers = 0
    public var adBreaks = 0
    public var adSeconds = 0
    public var snoozes = 0
    public var peakViewers = 0
    private var viewerTotal = 0
    private var viewerSamples = 0

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }

    /// The average of the viewer counts seen during the stream, nil before the first one.
    public var averageViewers: Int? {
        viewerSamples > 0 ? viewerTotal / viewerSamples : nil
    }

    public func duration(now: Date) -> TimeInterval {
        (endedAt ?? now).timeIntervalSince(startedAt)
    }

    public func isExpired(at now: Date) -> Bool {
        guard let endedAt else { return false }
        return now.timeIntervalSince(endedAt) > Self.keepFor
    }

    public mutating func record(viewers: Int) {
        peakViewers = max(peakViewers, viewers)
        viewerTotal += viewers
        viewerSamples += 1
    }

    public mutating func record(_ event: StudioEvent) {
        switch event {
        case .follow: followers += 1
        case .subscription(let value):
            if case .gift = value.kind {
                giftedSubscriptions += 1
            } else {
                subscriptions += 1
            }
        case .giftBomb(let value): giftedSubscriptions += value.count
        case .cheer(let value): bits += value.bits
        case .powerUp(let value): bits += value.bits
        case .raid(let value):
            raids += 1
            raidViewers += value.viewers
        case .adBreakBegan(let value):
            adBreaks += 1
            adSeconds += Int(value.duration)
        default:
            break
        }
    }

    public mutating func recordSnooze() {
        snoozes += 1
    }

    public mutating func end(at date: Date) {
        endedAt = date
    }
}
