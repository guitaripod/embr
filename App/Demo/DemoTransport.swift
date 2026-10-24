#if DEBUG
import Foundation
import EmbrCore

/// Answers every request locally with JSON shaped like the real services' replies, so the whole
/// app runs against the invented world in `DemoWorld`. Anything it does not know is a 404.
enum DemoTransport {
    static func response(for request: HTTPRequest) -> HTTPResponse {
        let url = request.url
        let path = url.path
        if url.host == "api.twitch.tv", path.hasPrefix("/helix/") {
            return helix(String(path.dropFirst("/helix/".count)), query: Query(url: url), request: request)
        }
        let mount = Configuration.current.workerBaseURL
        if url.host == mount.host, path.hasPrefix(mount.path) {
            return worker(path: String(path.dropFirst(mount.path.count)))
        }
        return notFound()
    }

    private struct Query {
        let items: [URLQueryItem]

        init(url: URL) {
            items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        }

        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        func values(_ name: String) -> [String] {
            items.filter { $0.name == name }.compactMap(\.value)
        }

        func int(_ name: String, default fallback: Int) -> Int {
            value(name).flatMap(Int.init) ?? fallback
        }
    }

    private static func helix(_ route: String, query: Query, request: HTTPRequest) -> HTTPResponse {
        switch route {
        case "streams": return streams(query: query, pool: DemoWorld.liveChannels, filtersByUserID: true)
        case "streams/followed":
            let followed = Set(DemoWorld.followedLogins)
            return streams(query: query, pool: DemoWorld.liveChannels.filter { followed.contains($0.login) }, filtersByUserID: false)
        case "games/top": return categories(DemoWorld.games, query: query)
        case "search/categories":
            let text = (query.value("query") ?? "").lowercased()
            return categories(DemoWorld.games.filter { $0.name.lowercased().contains(text) }, query: query)
        case "search/channels": return searchChannels(query: query)
        case "users": return users(query: query)
        case "channels": return channelInformation(query: query)
        case "videos": return videos(query: query)
        case "clips": return clips(query: query)
        case "channels/followed": return followedChannels(query: query)
        case "schedule": return schedule(query: query)
        case "chat/emotes/global": return emotes()
        case "chat/emotes": return json(["data": [Any]()])
        case "chat/badges/global", "chat/badges": return badges(route == "chat/badges/global")
        case "chat/settings":
            return json(["data": [[
                "emote_mode": false, "follower_mode": false, "slow_mode": false,
                "subscriber_mode": false, "unique_chat_mode": false
            ] as [String: Any]]])
        case "chat/messages":
            return json(["data": [["message_id": "demo-sent", "is_sent": true] as [String: Any]]])
        default: return notFound()
        }
    }

    private static func worker(path: String) -> HTTPResponse {
        if path == "/auth/app-token" {
            return json(["accessToken": "demo-app-token", "expiresIn": 14400])
        }
        if path == "/config" {
            return json(["livePlayback": "native"])
        }
        if path.hasPrefix("/playback/vod/") {
            let id = String(path.dropFirst("/playback/vod/".count))
            return json(["url": "https://\(DemoWorld.host)/hls/vod/\(id)/master.m3u8"])
        }
        if path.hasPrefix("/playback/clip/") {
            let slug = String(path.dropFirst("/playback/clip/".count))
            return json(["url": "https://\(DemoWorld.host)/hls/clips/\(slug)/master.m3u8"])
        }
        if path.hasPrefix("/playback/") {
            let login = String(path.dropFirst("/playback/".count))
            return json(["url": "https://\(DemoWorld.host)/hls/\(login)/master.m3u8"])
        }
        if path.hasPrefix("/events/") {
            return json(events(login: String(path.dropFirst("/events/".count))))
        }
        return notFound()
    }

    private static func notFound() -> HTTPResponse {
        HTTPResponse(status: 404, headers: [:], body: Data("{}".utf8))
    }

    private static func json(_ object: Any) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    private static func page(_ items: [[String: Any]], from query: Query, total: Int) -> HTTPResponse {
        let first = max(1, query.int("first", default: 20))
        let offset = query.value("after").flatMap(Int.init) ?? 0
        let slice = Array(items.dropFirst(offset).prefix(first))
        var body: [String: Any] = ["data": slice]
        if offset + first < total {
            body["pagination"] = ["cursor": String(offset + first)]
        } else {
            body["pagination"] = [String: Any]()
        }
        return json(body)
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func streamObject(_ channel: DemoChannel) -> [String: Any] {
        let game = DemoWorld.game(id: channel.gameID)
        return [
            "id": "5" + channel.id,
            "user_id": channel.id,
            "user_login": channel.login,
            "user_name": channel.name,
            "game_id": channel.gameID,
            "game_name": game?.name ?? "",
            "type": "live",
            "title": channel.title,
            "viewer_count": channel.viewers,
            "started_at": iso(DemoWorld.startedAt(of: channel)),
            "language": channel.language,
            "thumbnail_url": DemoWorld.thumbnailTemplate(login: channel.login),
            "tags": channel.tags,
            "is_mature": false
        ]
    }

    private static func streams(query: Query, pool: [DemoChannel], filtersByUserID: Bool) -> HTTPResponse {
        var matching = pool
        if filtersByUserID {
            let wanted = Set(query.values("user_id"))
            if !wanted.isEmpty { matching = matching.filter { wanted.contains($0.id) } }
        }
        if let gameID = query.value("game_id") {
            matching = matching.filter { $0.gameID == gameID }
        }
        return page(matching.map(streamObject), from: query, total: matching.count)
    }

    private static func categoryObject(_ game: DemoGame) -> [String: Any] {
        ["id": game.id, "name": game.name, "box_art_url": DemoWorld.boxArtTemplate(gameID: game.id)]
    }

    private static func categories(_ games: [DemoGame], query: Query) -> HTTPResponse {
        let ranked = games.sorted { viewers(of: $0) > viewers(of: $1) }
        return page(ranked.map(categoryObject), from: query, total: ranked.count)
    }

    private static func viewers(of game: DemoGame) -> Int {
        DemoWorld.channels.filter { $0.gameID == game.id }.reduce(0) { $0 + $1.viewers }
    }

    private static func searchChannels(query: Query) -> HTTPResponse {
        let text = (query.value("query") ?? "").lowercased()
        let liveOnly = query.value("live_only") == "true"
        let matches = DemoWorld.channels
            .filter { !liveOnly || $0.isLive }
            .filter { channel in
                let game = DemoWorld.game(id: channel.gameID)?.name.lowercased() ?? ""
                return channel.login.contains(text) || channel.name.lowercased().contains(text)
                    || game.contains(text) || channel.title.lowercased().contains(text)
            }
            .sorted { $0.viewers > $1.viewers }
        let items: [[String: Any]] = matches.map { channel in
            [
                "id": channel.id,
                "broadcaster_login": channel.login,
                "display_name": channel.name,
                "game_id": channel.gameID,
                "game_name": DemoWorld.game(id: channel.gameID)?.name ?? "",
                "title": channel.title,
                "is_live": channel.isLive,
                "tags": channel.tags,
                "thumbnail_url": DemoWorld.avatarURL(login: channel.login)
            ]
        }
        return page(items, from: query, total: items.count)
    }

    private static func users(query: Query) -> HTTPResponse {
        let logins = query.values("login").map { $0.lowercased() }
        let ids = query.values("id")
        let found = DemoWorld.channels.filter { logins.contains($0.login) || ids.contains($0.id) }
        var items: [[String: Any]] = found.map { channel in
            [
                "id": channel.id,
                "login": channel.login,
                "display_name": channel.name,
                "profile_image_url": DemoWorld.avatarURL(login: channel.login),
                "description": channel.bio,
                "broadcaster_type": channel.partner,
                "created_at": iso(Date().addingTimeInterval(-TimeInterval(channel.yearsOld) * 365 * 86400))
            ]
        }
        for login in logins where DemoWorld.channel(login: login) == nil && login != DemoWorld.userLogin {
            var generator = DemoRandom(seed: login)
            let identifier = "8" + String(Int(generator.next() % 90_000) + 10_000)
            items.append([
                "id": identifier, "login": login, "display_name": login,
                "profile_image_url": DemoWorld.avatarURL(login: login), "description": "Here for the chat.",
                "broadcaster_type": "", "created_at": iso(Date().addingTimeInterval(-2 * 365 * 86400))
            ])
        }
        if logins.contains(DemoWorld.userLogin) || ids.contains(DemoWorld.userID) {
            items.append([
                "id": DemoWorld.userID, "login": DemoWorld.userLogin, "display_name": "EmberFan",
                "profile_image_url": DemoWorld.avatarURL(login: DemoWorld.userLogin), "description": "",
                "broadcaster_type": "", "created_at": iso(Date().addingTimeInterval(-3 * 365 * 86400))
            ])
        }
        return json(["data": items])
    }

    private static func channelInformation(query: Query) -> HTTPResponse {
        guard let id = query.value("broadcaster_id"), let channel = DemoWorld.channel(id: id) else {
            return json(["data": [Any]()])
        }
        let title = channel.title.isEmpty ? "Back soon, thanks for stopping by" : channel.title
        return json(["data": [[
            "broadcaster_id": channel.id,
            "broadcaster_login": channel.login,
            "broadcaster_name": channel.name,
            "game_id": channel.gameID,
            "game_name": DemoWorld.game(id: channel.gameID)?.name ?? "",
            "title": title,
            "broadcaster_language": channel.language,
            "tags": channel.tags
        ] as [String: Any]]])
    }

    private static let vodTitles = [
        "Full run, start to finish", "Highlights: the comeback", "Community night, part 2",
        "Learning the new patch live", "Chill stream with requests", "The long one: 7 hours, no breaks"
    ]
    private static let clipTitles = [
        "That was not supposed to work", "Chat called it", "Cleanest finish of the week", "The cat joins the stream",
        "Perfect timing", "How is that even possible", "Chat goes quiet", "One more try"
    ]

    private static func videos(query: Query) -> HTTPResponse {
        guard let id = query.value("user_id"), let channel = DemoWorld.channel(id: id) else {
            return json(["data": [Any]()])
        }
        let durations = ["3h41m12s", "42m8s", "2h5m33s", "1h17m20s", "4h2m9s", "7h11m48s"]
        let kinds = ["archive", "highlight", "archive", "archive", "upload", "archive"]
        let items: [[String: Any]] = (0..<6).map { index in
            let created = Date().addingTimeInterval(-TimeInterval(index * 2 + 1) * 86400)
            return [
                "id": "vod-\(channel.login)-\(index)",
                "user_id": channel.id,
                "user_login": channel.login,
                "user_name": channel.name,
                "title": vodTitles[index],
                "created_at": iso(created),
                "published_at": iso(created),
                "thumbnail_url": "https://\(DemoWorld.host)/vod/\(channel.login)\(index)/%{width}x%{height}",
                "view_count": 38000 / (index + 2) + 211 * index,
                "duration": durations[index],
                "type": kinds[index]
            ]
        }
        return page(items, from: query, total: items.count)
    }

    private static func clips(query: Query) -> HTTPResponse {
        guard let id = query.value("broadcaster_id"), let channel = DemoWorld.channel(id: id) else {
            return json(["data": [Any]()])
        }
        let creators = ["tavernbard", "mapleowl", "quickbrownfox", "sundial", "nimbusnick", "cobblestone", "plumline", "harbourlight"]
        let items: [[String: Any]] = (0..<8).map { index in
            let views: Int = 9400 / (index + 1) + 37 * index
            let created = Date().addingTimeInterval(-TimeInterval(index * 3 + 1) * 86400)
            return [
                "id": "clip-\(channel.login)-\(index)",
                "broadcaster_id": channel.id,
                "broadcaster_name": channel.name,
                "creator_name": creators[index],
                "title": clipTitles[index],
                "view_count": views,
                "created_at": iso(created),
                "thumbnail_url": "https://\(DemoWorld.host)/clip/\(channel.login)\(index + 1)/480x272",
                "duration": 18.0 + Double(index) * 4.5,
                "url": "https://\(DemoWorld.host)/clips/\(channel.login)-\(index)"
            ]
        }
        return page(items, from: query, total: items.count)
    }

    private static func followedChannels(query: Query) -> HTTPResponse {
        let items: [[String: Any]] = DemoWorld.followedLogins.enumerated().compactMap { index, login in
            guard let channel = DemoWorld.channel(login: login) else { return nil }
            return [
                "broadcaster_id": channel.id,
                "broadcaster_login": channel.login,
                "broadcaster_name": channel.name,
                "followed_at": iso(Date().addingTimeInterval(-TimeInterval(index + 2) * 30 * 86400))
            ]
        }
        return page(items, from: query, total: items.count)
    }

    private static func schedule(query: Query) -> HTTPResponse {
        guard let id = query.value("broadcaster_id"), let channel = DemoWorld.channel(id: id) else {
            return json(["data": ["segments": [Any]()]])
        }
        let game = DemoWorld.game(id: channel.gameID)
        let segments: [[String: Any]] = (0..<4).map { index in
            let start = Date().addingTimeInterval(TimeInterval(index + 1) * 86400 + 3600 * 2)
            return [
                "id": "seg-\(channel.login)-\(index)",
                "start_time": iso(start),
                "end_time": iso(start.addingTimeInterval(3600 * 3)),
                "title": ["Evening session", "Community night", "Weekend marathon", "Q&A and chill"][index],
                "category": ["id": channel.gameID, "name": game?.name ?? ""],
                "is_recurring": index % 2 == 0
            ]
        }
        return json(["data": ["segments": segments]])
    }

    private static func emotes() -> HTTPResponse {
        let items: [[String: Any]] = DemoWorld.emoteNames.map { name in
            [
                "id": "demo-\(name)",
                "name": name,
                "images": [
                    "url_1x": "https://\(DemoWorld.host)/emote/\(name)/1",
                    "url_2x": "https://\(DemoWorld.host)/emote/\(name)/2",
                    "url_4x": "https://\(DemoWorld.host)/emote/\(name)/4"
                ],
                "format": ["static"],
                "scale": ["1.0", "2.0", "3.0"],
                "theme_mode": ["dark"],
                "emote_type": "globals"
            ]
        }
        return json(["data": items])
    }

    private static func badges(_ global: Bool) -> HTTPResponse {
        guard global else { return json(["data": [Any]()]) }
        let titles = ["broadcaster": "Broadcaster", "moderator": "Moderator", "subscriber": "Subscriber", "vip": "VIP"]
        let items: [[String: Any]] = titles.map { set, title in
            [
                "set_id": set,
                "versions": [[
                    "id": "1",
                    "image_url_1x": "https://\(DemoWorld.host)/badge/\(set)/1",
                    "image_url_2x": "https://\(DemoWorld.host)/badge/\(set)/2",
                    "image_url_4x": "https://\(DemoWorld.host)/badge/\(set)/4",
                    "title": title,
                    "description": title
                ] as [String: Any]]
            ]
        }
        return json(["data": items])
    }

    private static func events(login: String) -> [String: Any] {
        let now = Date().timeIntervalSince1970
        switch login {
        case "lumenfox":
            return [
                "poll": [
                    "id": "poll-1", "title": "Which loadout next run?", "status": "ACTIVE", "endsAt": now + 140, "totalVotes": 1893,
                    "choices": [["title": "Glass cannon", "votes": 902], ["title": "Tank build", "votes": 611], ["title": "Chaos mode", "votes": 380]]
                ] as [String: Any]
            ]
        case "northerncrane":
            return [
                "prediction": [
                    "id": "prediction-1", "title": "Does the next game end in a win?", "status": "ACTIVE", "locksAt": now + 210,
                    "outcomes": [
                        ["title": "Yes", "color": "BLUE", "points": 482_000, "users": 1210],
                        ["title": "No", "color": "PINK", "points": 311_000, "users": 874]
                    ]
                ] as [String: Any]
            ]
        default:
            return ["poll": NSNull(), "prediction": NSNull()]
        }
    }
}
#endif
