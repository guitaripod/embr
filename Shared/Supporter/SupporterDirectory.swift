import Foundation
import os
import EmbrCore
import MidgarCore

/// Embr's Founding Supporters as the worker lists them: each one's Twitch user id, founding number, flame color and
/// name style, so chat can draw their badge and name for every Embr viewer. The last list is kept on the device, so
/// the badges show before the first refresh of a launch.
final class SupporterDirectory: Sendable {
    static let shared = SupporterDirectory()

    /// The look chat gives a supporter's messages.
    struct Look: Sendable, Equatable {
        let badge: Badge
        let color: SupporterAccent
        let nameStyle: SupporterAPI.NameStyle
        let number: Int?
    }

    private let profiles: OSAllocatedUnfairLock<[String: SupporterAPI.Profile]>
    private let total = OSAllocatedUnfairLock<Int>(initialState: 0)
    private let changeCount = OSAllocatedUnfairLock<Int>(initialState: 0)
    private let lastRefresh = OSAllocatedUnfairLock<Date?>(initialState: nil)
    private let pinned = OSAllocatedUnfairLock<(id: String, profile: SupporterAPI.Profile)?>(initialState: nil)
    private let transport: HTTPTransport
    private let endpoints: WorkerEndpoints
    /// UserDefaults is safe to use from any thread; it predates Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults
    private static let cacheKey = "supporters.directory.v2"
    private static let legacyCacheKey = "supporters.directory.v1"
    private static let refreshInterval: TimeInterval = 30 * 60

    init(
        transport: HTTPTransport = MidgarGatewayTransport.shared,
        endpoints: WorkerEndpoints = WorkerEndpoints(baseURL: Configuration.current.workerBaseURL),
        defaults: UserDefaults = .standard
    ) {
        self.transport = transport
        self.endpoints = endpoints
        self.defaults = defaults
        let cached = Self.cachedDirectory(defaults)
        profiles = OSAllocatedUnfairLock(initialState: cached.resolvedProfiles)
        total.withLock { $0 = cached.supporterCount }
    }

    func contains(_ userID: String) -> Bool {
        guard !userID.isEmpty else { return false }
        return profiles.withLock { $0[userID] != nil }
    }

    /// The person's own badge, kept through a refresh: the worker's list is cached for minutes, so a badge claimed or
    /// restyled just now would otherwise vanish from this device until the cache catches up.
    func pin(_ userID: String, profile: SupporterAPI.Profile) {
        let previous = pinned.withLock { pinned -> String? in
            defer { pinned = (userID, profile) }
            return pinned?.id
        }
        if let previous, previous != userID {
            remove(previous)
        }
        insert(userID, profile: profile)
    }

    /// Stops keeping the person's own badge through refreshes, and takes it off this device.
    func unpin() {
        guard let own = pinned.withLock({ pinned -> (id: String, profile: SupporterAPI.Profile)? in
            defer { pinned = nil }
            return pinned
        }) else { return }
        remove(own.id)
    }

    func profile(for userID: String) -> SupporterAPI.Profile? {
        guard !userID.isEmpty else { return nil }
        return profiles.withLock { $0[userID] }
    }

    /// The badge, color and name style of a supporter's messages, or nil for everyone else.
    func look(for userID: String) -> Look? {
        guard let profile = profile(for: userID) else { return nil }
        let color = SupporterAccent(rawValue: profile.color) ?? .violet
        return Look(badge: color.badge, color: color, nameStyle: profile.style, number: profile.number)
    }

    /// How many Founding Supporters there are, as of the last list.
    var count: Int {
        total.withLock { $0 }
    }

    /// Goes up whenever a supporter's look may have changed, so open chats know to draw their messages again.
    var revision: Int {
        changeCount.withLock { $0 }
    }

    /// Shows the person's own badge and look at once after a claim or a style change, before the next refresh brings
    /// them back from the worker.
    func insert(_ userID: String, profile: SupporterAPI.Profile) {
        let added = profiles.withLock { profiles in
            let isNew = profiles[userID] == nil
            profiles[userID] = profile
            return isNew
        }
        if added {
            total.withLock { $0 += 1 }
        }
        changeCount.withLock { $0 += 1 }
        persist()
    }

    /// Takes a supporter's badge off this device at once: a refund, or a badge that moved to another account.
    func remove(_ userID: String) {
        let removed = profiles.withLock { $0.removeValue(forKey: userID) != nil }
        guard removed else { return }
        total.withLock { $0 = max(0, $0 - 1) }
        changeCount.withLock { $0 += 1 }
        persist()
    }

    /// Reads the list again unless it was read in the last half hour.
    func refreshIfStale(now: Date = Date()) async {
        guard EmbrMidgar.reachesMidgarServices else { return }
        let due = lastRefresh.withLock { last in
            guard let last, now.timeIntervalSince(last) < Self.refreshInterval else { return true }
            return false
        }
        guard due else { return }
        await refresh(now: now)
    }

    private func refresh(now: Date) async {
        do {
            let response = try await transport.send(endpoints.supporters())
            guard response.isSuccess else {
                MidgarLog.notice("supporter directory: status \(response.status)", category: .supporter)
                return
            }
            let directory = try WorkerEndpoints.decodeSupporterDirectory(response.body)
            let own = pinned.withLock { $0 }
            profiles.withLock { profiles in
                profiles = directory.resolvedProfiles
                if let own { profiles[own.id] = own.profile }
            }
            total.withLock { $0 = directory.supporterCount }
            changeCount.withLock { $0 += 1 }
            lastRefresh.withLock { $0 = now }
            persist()
            MidgarLog.info("supporter directory: \(directory.supporters.count) supporters", category: .supporter)
        } catch {
            MidgarLog.notice("supporter directory refresh failed: \(error)", category: .supporter)
        }
    }

    private func persist() {
        let current = profiles.withLock { $0 }
        let directory = SupporterAPI.Directory(supporters: Array(current.keys), profiles: current, count: count)
        if let data = try? JSONEncoder().encode(directory) {
            defaults.set(data, forKey: Self.cacheKey)
        }
    }

    /// The last list kept on the device, or the ids-only list an earlier build kept.
    private static func cachedDirectory(_ defaults: UserDefaults) -> SupporterAPI.Directory {
        if let data = defaults.data(forKey: cacheKey), let directory = try? JSONDecoder().decode(SupporterAPI.Directory.self, from: data) {
            return directory
        }
        return SupporterAPI.Directory(supporters: defaults.stringArray(forKey: legacyCacheKey) ?? [])
    }
}
