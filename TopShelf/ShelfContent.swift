import TVServices
import EmbrCore
import MidgarCore

/// Builds the Top Shelf from the app's snapshot and a fresh look at who is live.
enum ShelfContent {
    struct Plan: Sendable {
        let entries: [ShelfPlanner.Entry]
        let previews: [String: URL]
    }

    /// How old the app's own list of live streams may be when Twitch cannot be reached.
    private static let staleLimit: TimeInterval = 20 * 60
    private static let previewCount = 3

    static func plan() async -> Plan? {
        guard let snapshot = TopShelfSnapshotStore.load() else { return nil }
        let live = await ShelfLiveClient.liveStreams(userIDs: snapshot.channelIDs)
            ?? (Date().timeIntervalSince(snapshot.updatedAt) < staleLimit ? snapshot.live.map(\.liveStream) : [])
        let entries = ShelfPlanner.entries(live: live, favoriteIDs: Set(snapshot.favoriteIDs))
        guard !entries.isEmpty else { return nil }
        let previews = snapshot.previews
            ? await ShelfLiveClient.previews(logins: entries.prefix(previewCount).map(\.stream.userLogin))
            : [:]
        return Plan(entries: entries, previews: previews)
    }

    static func carousel(for plan: Plan) -> TVTopShelfCarouselContent {
        TVTopShelfCarouselContent(style: .details, items: plan.entries.map { item(for: $0, preview: plan.previews[$0.stream.userLogin]) })
    }

    private static func item(for entry: ShelfPlanner.Entry, preview: URL?) -> TVTopShelfCarouselItem {
        let stream = entry.stream
        let item = TVTopShelfCarouselItem(identifier: stream.userLogin)
        item.title = stream.userName.isEmpty ? stream.userLogin : stream.userName
        item.contextTitle = entry.isFavorite
            ? String(localized: "Live · Favorite", comment: "Top Shelf label above a favorite channel that is live")
            : String(localized: "Live Now", comment: "Top Shelf label above a followed channel that is live")
        item.summary = stream.title
        item.genre = stream.gameName.isEmpty ? nil : stream.gameName
        item.creationDate = stream.startedAt
        item.mediaOptions = [.videoResolutionHD]
        item.namedAttributes = [
            TVTopShelfNamedAttribute(
                name: String(localized: "Viewers", comment: "Top Shelf attribute name"),
                values: [stream.viewerCount.formatted(.number.notation(.compactName))]
            ),
        ]
        item.setImageURL(cacheBusted(stream.thumbnailURL(width: 1920, height: 1080)), for: .screenScale1x)
        item.setImageURL(cacheBusted(stream.thumbnailURL(width: 1920, height: 1080)), for: .screenScale2x)
        item.previewVideoURL = preview
        item.playAction = TVTopShelfAction(url: EmbrLink.watch(login: stream.userLogin).url)
        item.displayAction = TVTopShelfAction(url: EmbrLink.channel(login: stream.userLogin).url)
        return item
    }

    /// Twitch serves the same thumbnail URL for hours while the picture changes every few minutes; a query that
    /// changes every five minutes makes the system fetch the current one.
    private static func cacheBusted(_ url: URL?) -> URL? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let slot = Int(Date().timeIntervalSince1970 / 300)
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "t", value: String(slot))]
        return components.url ?? url
    }
}
