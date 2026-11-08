import Foundation

/// What Twitch's Ads Manager says about the channel's ad breaks, from Get Ad Schedule or Snooze Next Ad.
public struct AdSchedule: Sendable, Equatable {
    public let nextAdAt: Date?
    public let lastAdAt: Date?
    public let duration: TimeInterval
    public let prerollFreeSeconds: TimeInterval
    public let snoozeCount: Int
    public let snoozeRefreshAt: Date?
    public let fetchedAt: Date

    public init(nextAdAt: Date?, lastAdAt: Date?, duration: TimeInterval, prerollFreeSeconds: TimeInterval, snoozeCount: Int, snoozeRefreshAt: Date?, fetchedAt: Date) {
        self.nextAdAt = nextAdAt
        self.lastAdAt = lastAdAt
        self.duration = duration
        self.prerollFreeSeconds = prerollFreeSeconds
        self.snoozeCount = snoozeCount
        self.snoozeRefreshAt = snoozeRefreshAt
        self.fetchedAt = fetchedAt
    }
}

/// The ad clock's five states, worked out from the last schedule Twitch sent, the last ad break that began and the time
/// now, so the countdown runs on the device between reads and a missed event can't leave it stuck.
public struct AdBreakClock: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        /// Nothing is known yet, or the channel is offline: Twitch schedules no ads then.
        case unknown
        /// No mid-roll is scheduled; pre-rolls are off until the date, when there is one.
        case noneScheduled(prerollFreeUntil: Date?)
        /// A mid-roll more than a minute away.
        case scheduled(at: Date, duration: TimeInterval)
        /// A mid-roll a minute away or less.
        case imminent(at: Date, duration: TimeInterval)
        /// Viewers are watching ads until the date.
        case running(endsAt: Date, duration: TimeInterval)
    }

    /// The warnings a streamer can hear before a mid-roll.
    public enum Warning: Sendable, Equatable {
        case oneMinute
        case tenSeconds
    }

    public static let imminentWindow: TimeInterval = 60
    /// Twitch refuses a new ad within this long of the last one.
    public static let cooldown: TimeInterval = 8 * 60
    /// The lengths Run Ad offers, in seconds; Twitch caps a break at 180.
    public static let lengths: [Int] = [30, 60, 90, 120, 150, 180]

    public private(set) var schedule: AdSchedule?
    public private(set) var lastBreak: StudioAdBreak?
    /// When Twitch said it would take the next manual ad, after refusing one.
    public private(set) var retryAfter: Date?

    public init(schedule: AdSchedule? = nil, lastBreak: StudioAdBreak? = nil) {
        self.schedule = schedule
        self.lastBreak = lastBreak
    }

    public mutating func apply(_ schedule: AdSchedule) {
        self.schedule = schedule
    }

    public mutating func apply(_ adBreak: StudioAdBreak) {
        lastBreak = adBreak
    }

    public mutating func refuseManualAd(until date: Date) {
        retryAfter = date
    }

    public mutating func reset() {
        schedule = nil
        lastBreak = nil
        retryAfter = nil
    }

    public func state(at now: Date) -> State {
        if let lastBreak, now >= lastBreak.startedAt, now < lastBreak.endsAt {
            return .running(endsAt: lastBreak.endsAt, duration: lastBreak.duration)
        }
        guard let schedule else { return .unknown }
        if let next = schedule.nextAdAt {
            if now >= next {
                let ends = next.addingTimeInterval(schedule.duration)
                if now < ends, !startedBreak(near: next) {
                    return .running(endsAt: ends, duration: schedule.duration)
                }
                return .noneScheduled(prerollFreeUntil: prerollFreeUntil(schedule))
            }
            let remaining = next.timeIntervalSince(now)
            return remaining <= Self.imminentWindow
                ? .imminent(at: next, duration: schedule.duration)
                : .scheduled(at: next, duration: schedule.duration)
        }
        return .noneScheduled(prerollFreeUntil: prerollFreeUntil(schedule))
    }

    /// When Run Ad becomes available again, or nil when it already is.
    public func runAdUnlocksAt(now: Date) -> Date? {
        let starts = [schedule?.lastAdAt, lastBreak?.startedAt].compactMap { $0 }
        let cooldownEnd = starts.max().map { $0.addingTimeInterval(Self.cooldown) }
        let latest = [cooldownEnd, retryAfter].compactMap { $0 }.max()
        guard let latest, latest > now else { return nil }
        return latest
    }

    public func canSnooze(at now: Date) -> Bool {
        guard let schedule, schedule.snoozeCount > 0 else { return false }
        switch state(at: now) {
        case .scheduled, .imminent: return true
        default: return false
        }
    }

    public func canRunAd(at now: Date) -> Bool {
        if case .running = state(at: now) { return false }
        guard schedule != nil else { return false }
        return runAdUnlocksAt(now: now) == nil
    }

    public var snoozesLeft: Int { schedule?.snoozeCount ?? 0 }
    public var nextSnoozeAt: Date? { schedule?.snoozeRefreshAt }

    /// The warning to sound between two ticks of the clock: one when the countdown crossed a minute, another when it
    /// crossed ten seconds. Nil when neither was crossed.
    public func warning(between previous: Date, and now: Date) -> Warning? {
        guard let next = schedule?.nextAdAt, now < next, previous < now else { return nil }
        let before = next.timeIntervalSince(previous)
        let after = next.timeIntervalSince(now)
        if before > 10, after <= 10 { return .tenSeconds }
        if before > Self.imminentWindow, after <= Self.imminentWindow { return .oneMinute }
        return nil
    }

    private func prerollFreeUntil(_ schedule: AdSchedule) -> Date? {
        guard schedule.prerollFreeSeconds > 0 else { return nil }
        return schedule.fetchedAt.addingTimeInterval(schedule.prerollFreeSeconds)
    }

    /// Whether the last break that began belongs to the scheduled slot, so the slot isn't counted as running twice.
    private func startedBreak(near date: Date) -> Bool {
        guard let lastBreak else { return false }
        return abs(lastBreak.startedAt.timeIntervalSince(date)) < 90
    }
}
