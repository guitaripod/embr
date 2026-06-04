import Foundation
import EmbrCore

actor EmoteService: EmoteCataloging {
    static let shared = EmoteService()

    private let api: TwitchAPIProviding
    private let sevenTV: ThirdPartyEmoteSource
    private let bttv: ThirdPartyEmoteSource
    private let ffz: ThirdPartyEmoteSource

    private let ttl: TimeInterval = 600
    private let retryTTL: TimeInterval = 15

    private struct CacheEntry {
        let emotes: EmoteCatalog
        let badges: BadgeCatalog
        let storedAt: Date
        let isEmpty: Bool
    }

    private var globalCache: CacheEntry?
    private var channelCache: [String: CacheEntry] = [:]

    init(
        api: TwitchAPIProviding = TwitchAPIClient.shared,
        sevenTV: ThirdPartyEmoteSource = SevenTVSource(),
        bttv: ThirdPartyEmoteSource = BetterTTVSource(),
        ffz: ThirdPartyEmoteSource = FrankerFaceZSource()
    ) {
        self.api = api
        self.sevenTV = sevenTV
        self.bttv = bttv
        self.ffz = ffz
    }

    func loadGlobal() async -> (emotes: EmoteCatalog, badges: BadgeCatalog) {
        if let cached = globalCache, !isStale(cached) {
            return (cached.emotes, cached.badges)
        }

        async let twitchEmotes = fetchTwitchGlobalEmotes()
        async let sevenEmotes = sevenTV.fetchGlobal()
        async let bttvEmotes = bttv.fetchGlobal()
        async let ffzEmotes = ffz.fetchGlobal()
        async let twitchBadges = fetchTwitchGlobalBadges()

        let merged = EmoteCatalog.merge([
            .twitch: await twitchEmotes,
            .sevenTV: await sevenEmotes,
            .betterTTV: await bttvEmotes,
            .frankerFaceZ: await ffzEmotes
        ])

        var catalog = EmoteCatalog()
        catalog.setGlobal(merged)

        let twitchBadgeDict = twitchBadgeMap(await twitchBadges)
        var badgeCatalog = BadgeCatalog()
        badgeCatalog.setTwitch(twitchBadgeDict)

        let entry = CacheEntry(
            emotes: catalog,
            badges: badgeCatalog,
            storedAt: Date(),
            isEmpty: merged.isEmpty && twitchBadgeDict.isEmpty
        )
        globalCache = entry
        AppLogger.shared.info("Loaded \(merged.count) global emotes", category: .emote)
        return (catalog, badgeCatalog)
    }

    func loadChannel(broadcasterID: String, login: String) async -> (emotes: EmoteCatalog, badges: BadgeCatalog) {
        if let cached = channelCache[broadcasterID], !isStale(cached) {
            return (cached.emotes, cached.badges)
        }

        let globalLoad = await loadGlobal()

        async let twitchEmotes = fetchTwitchChannelEmotes(broadcasterID: broadcasterID)
        async let sevenEmotes = sevenTV.fetchChannel(twitchUserID: broadcasterID)
        async let bttvEmotes = bttv.fetchChannel(twitchUserID: broadcasterID)
        async let ffzEmotes = ffz.fetchChannel(twitchUserID: broadcasterID)
        async let channelBadges = fetchTwitchChannelBadges(broadcasterID: broadcasterID)

        let merged = EmoteCatalog.merge([
            .twitch: await twitchEmotes,
            .sevenTV: await sevenEmotes,
            .betterTTV: await bttvEmotes,
            .frankerFaceZ: await ffzEmotes
        ])

        var catalog = EmoteCatalog(global: globalLoad.emotes.global)
        catalog.setChannel(merged)

        var twitch = globalLoad.badges.twitch
        for (key, badge) in twitchBadgeMap(await channelBadges) {
            twitch[key] = badge
        }
        var badgeCatalog = BadgeCatalog()
        badgeCatalog.setTwitch(twitch)

        let entry = CacheEntry(
            emotes: catalog,
            badges: badgeCatalog,
            storedAt: Date(),
            isEmpty: globalLoad.emotes.global.isEmpty
        )
        channelCache[broadcasterID] = entry
        AppLogger.shared.info("Loaded \(merged.count) channel emotes for \(login)", category: .emote)
        return (catalog, badgeCatalog)
    }

    private func isStale(_ entry: CacheEntry) -> Bool {
        Date().timeIntervalSince(entry.storedAt) > (entry.isEmpty ? retryTTL : ttl)
    }

    private func twitchBadgeMap(_ badges: [Badge]) -> [String: Badge] {
        var map: [String: Badge] = [:]
        for badge in badges {
            map[Badge.key(setID: badge.setID, version: badge.version)] = badge
        }
        return map
    }

    private nonisolated func fetchTwitchGlobalEmotes() async -> [Emote] {
        do { return try await api.globalEmotes() }
        catch { AppLogger.shared.warn("Twitch global emotes failed: \(error)", category: .emote); return [] }
    }

    private nonisolated func fetchTwitchChannelEmotes(broadcasterID: String) async -> [Emote] {
        do { return try await api.channelEmotes(broadcasterID: broadcasterID) }
        catch { AppLogger.shared.warn("Twitch channel emotes failed: \(error)", category: .emote); return [] }
    }

    private nonisolated func fetchTwitchGlobalBadges() async -> [Badge] {
        do { return try await api.globalBadges() }
        catch { AppLogger.shared.warn("Twitch global badges failed: \(error)", category: .emote); return [] }
    }

    private nonisolated func fetchTwitchChannelBadges(broadcasterID: String) async -> [Badge] {
        do { return try await api.channelBadges(broadcasterID: broadcasterID) }
        catch { AppLogger.shared.warn("Twitch channel badges failed: \(error)", category: .emote); return [] }
    }
}

private extension ThirdPartyEmoteSource {
    func fetchGlobal() async -> [Emote] {
        (try? await globalEmotes()) ?? []
    }

    func fetchChannel(twitchUserID: String) async -> [Emote] {
        (try? await channelEmotes(twitchUserID: twitchUserID)) ?? []
    }
}
