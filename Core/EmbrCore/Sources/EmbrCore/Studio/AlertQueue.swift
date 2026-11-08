import Foundation

/// How loud a moment is. One means it changes what the streamer does next; four only goes in the feed.
public enum StudioPriority: Int, Sendable, Comparable {
    case urgent = 1
    case big = 2
    case notable = 3
    case quiet = 4

    public static func < (lhs: StudioPriority, rhs: StudioPriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The sounds Studio can play through the TV, one per kind of moment.
public enum StudioSound: String, CaseIterable, Sendable, Codable {
    case adWarning
    case raid
    case hypeTrain
    case gift
    case bits
    case subscription
    case goal
    case follow
    case redemption
    case alarm
}

/// The kinds of alert a streamer can switch on or off.
public enum StudioAlertKind: String, CaseIterable, Sendable, Codable {
    case follows
    case subscriptions
    case giftBombs
    case cheers
    case powerUps
    case raids
    case redemptions
    case charity
}

/// One line of the alert feed. Follows that arrive close together share a line.
public struct StudioFeedItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let event: StudioEvent
    public let at: Date
    public let isBig: Bool
    /// The other followers folded into a follow line, newest first.
    public let moreFollowers: [String]

    public init(id: String, event: StudioEvent, at: Date, isBig: Bool, moreFollowers: [String] = []) {
        self.id = id
        self.event = event
        self.at = at
        self.isBig = isBig
        self.moreFollowers = moreFollowers
    }
}

/// A moment that takes the space over chat for a while: a raid, a big gift bomb, a big cheer.
public struct StudioBanner: Sendable, Equatable, Identifiable {
    public let id: String
    public let event: StudioEvent
    public let priority: StudioPriority
    public let duration: TimeInterval

    public init(id: String, event: StudioEvent, priority: StudioPriority, duration: TimeInterval) {
        self.id = id
        self.event = event
        self.priority = priority
        self.duration = duration
    }
}

/// Which alerts show and sound, and what counts as a big moment.
public struct AlertPreferences: Sendable, Equatable, Codable {
    public var shown: Set<StudioAlertKind>
    public var sounds: Set<StudioSound>
    public var giftBombMinimum: Int
    public var cheerMinimum: Int
    public var batchesFollows: Bool

    public init(
        shown: Set<StudioAlertKind> = Set(StudioAlertKind.allCases),
        sounds: Set<StudioSound> = [.adWarning, .raid, .hypeTrain, .gift, .bits, .subscription, .goal, .alarm],
        giftBombMinimum: Int = 5,
        cheerMinimum: Int = 1000,
        batchesFollows: Bool = true
    ) {
        self.shown = shown
        self.sounds = sounds
        self.giftBombMinimum = giftBombMinimum
        self.cheerMinimum = cheerMinimum
        self.batchesFollows = batchesFollows
    }

    /// Every sound off, for a room where the microphone can hear the TV.
    public static let silent = AlertPreferences(sounds: [])
}

/// Sorts Studio's events into the alert feed and the banners over chat, and says which sound each one makes. The queue
/// shows one banner at a time, the most urgent first, so two loud moments never fight for the same space.
public struct AlertQueue: Sendable {
    public struct Outcome: Sendable, Equatable {
        public var feedChanged = false
        public var sound: StudioSound?

        public init(feedChanged: Bool = false, sound: StudioSound? = nil) {
            self.feedChanged = feedChanged
            self.sound = sound
        }
    }

    public static let feedLimit = 40
    public static let followWindow: TimeInterval = 20

    public private(set) var feed: [StudioFeedItem] = []
    public private(set) var banner: StudioBanner?
    public private(set) var bannerEndsAt: Date?
    private var waiting: [StudioBanner] = []
    private var seen: [String] = []

    public var preferences: AlertPreferences

    public init(preferences: AlertPreferences = AlertPreferences()) {
        self.preferences = preferences
    }

    /// Takes one event in. Events that are not alerts (stream state, polls, hype trains) are left to the caller.
    public mutating func ingest(_ event: StudioEvent, at now: Date) -> Outcome {
        guard let kind = Self.kind(of: event), preferences.shown.contains(kind) else { return Outcome() }
        let id = Self.identity(of: event, at: now)
        guard !seen.contains(id) else { return Outcome() }
        remember(id)
        let big = isBig(event)
        var outcome = Outcome(feedChanged: true, sound: sound(for: event, big: big))
        if case .follow(let follow) = event, preferences.batchesFollows,
           let first = feed.first, case .follow(let newest) = first.event,
           now.timeIntervalSince(first.at) <= Self.followWindow {
            feed[0] = StudioFeedItem(id: first.id, event: .follow(follow), at: now, isBig: false, moreFollowers: [newest.userName] + first.moreFollowers)
            outcome.sound = nil
            return outcome
        }
        feed.insert(StudioFeedItem(id: id, event: event, at: now, isBig: big), at: 0)
        if feed.count > Self.feedLimit { feed.removeLast(feed.count - Self.feedLimit) }
        if let banner = banner(for: event, id: id, big: big) {
            enqueue(banner, at: now)
        }
        return outcome
    }

    /// Ends a banner whose time is up and shows the next one waiting. Returns whether the banner changed.
    public mutating func tick(at now: Date) -> Bool {
        guard let ends = bannerEndsAt, now >= ends else { return false }
        banner = nil
        bannerEndsAt = nil
        showNext(at: now)
        return true
    }

    /// Takes the banner down at once, as when the streamer dismisses it.
    public mutating func dismissBanner(at now: Date) {
        banner = nil
        bannerEndsAt = nil
        showNext(at: now)
    }

    public mutating func clear() {
        feed = []
        banner = nil
        bannerEndsAt = nil
        waiting = []
    }

    public static func kind(of event: StudioEvent) -> StudioAlertKind? {
        switch event {
        case .follow: .follows
        case .subscription: .subscriptions
        case .giftBomb: .giftBombs
        case .cheer: .cheers
        case .powerUp: .powerUps
        case .raid: .raids
        case .redemption: .redemptions
        case .charity: .charity
        default: nil
        }
    }

    public func priority(of event: StudioEvent) -> StudioPriority {
        switch event {
        case .raid: .urgent
        case .giftBomb, .cheer, .charity: isBig(event) ? .big : .notable
        case .subscription: .notable
        default: .quiet
        }
    }

    private func isBig(_ event: StudioEvent) -> Bool {
        switch event {
        case .raid: true
        case .giftBomb(let bomb): bomb.count >= preferences.giftBombMinimum
        case .cheer(let cheer): cheer.bits >= preferences.cheerMinimum
        case .charity: true
        default: false
        }
    }

    private func sound(for event: StudioEvent, big: Bool) -> StudioSound? {
        let sound: StudioSound? = switch event {
        case .raid: .raid
        case .giftBomb: .gift
        case .cheer, .powerUp: .bits
        case .subscription: .subscription
        case .follow: .follow
        case .redemption: .redemption
        case .charity: .gift
        default: nil
        }
        guard let sound, preferences.sounds.contains(sound) else { return nil }
        return sound
    }

    private func banner(for event: StudioEvent, id: String, big: Bool) -> StudioBanner? {
        guard big else { return nil }
        switch event {
        case .raid: return StudioBanner(id: id, event: event, priority: .urgent, duration: 12)
        case .giftBomb, .cheer, .charity: return StudioBanner(id: id, event: event, priority: .big, duration: 8)
        default: return nil
        }
    }

    private mutating func enqueue(_ banner: StudioBanner, at now: Date) {
        if let current = self.banner, banner.priority < current.priority {
            waiting.insert(current, at: 0)
            self.banner = banner
            bannerEndsAt = now.addingTimeInterval(banner.duration)
            return
        }
        waiting.append(banner)
        waiting.sort { $0.priority < $1.priority }
        if self.banner == nil { showNext(at: now) }
    }

    private mutating func showNext(at now: Date) {
        guard !waiting.isEmpty else { return }
        let next = waiting.removeFirst()
        banner = next
        bannerEndsAt = now.addingTimeInterval(next.duration)
    }

    private mutating func remember(_ id: String) {
        seen.append(id)
        if seen.count > 200 { seen.removeFirst(seen.count - 200) }
    }

    /// A stable id per real-world moment, so the same alert delivered twice (a reconnect, a replayed notification)
    /// shows once.
    static func identity(of event: StudioEvent, at now: Date) -> String {
        switch event {
        case .follow(let value): "follow-\(value.userID)"
        case .subscription(let value): "sub-\(value.id)"
        case .giftBomb(let value): "bomb-\(value.id)"
        case .cheer(let value): "cheer-\(value.id)"
        case .powerUp(let value): "power-\(value.userID)-\(Int(now.timeIntervalSince1970))"
        case .raid(let value): "raid-\(value.raiderID)-\(Int(now.timeIntervalSince1970 / 60))"
        case .redemption(let value): "redeem-\(value.id)"
        case .charity(let value): "charity-\(value.userID)-\(value.minorUnits)-\(Int(now.timeIntervalSince1970 / 10))"
        default: UUID().uuidString
        }
    }
}
