import Foundation

public struct HelixRequestFactory: Sendable {
    public let clientID: String
    public let baseURL: URL

    public init(clientID: String, baseURL: URL = URL(string: "https://api.twitch.tv/helix")!) {
        self.clientID = clientID
        self.baseURL = baseURL
    }

    public func topStreams(first: Int = 20, after: String? = nil, token: String) -> HTTPRequest {
        get(
            "streams",
            items: [
                ("type", "live"),
                ("first", String(first)),
                ("after", after)
            ],
            token: token
        )
    }

    public func streamsByGame(gameID: String, first: Int = 20, after: String? = nil, token: String) -> HTTPRequest {
        get(
            "streams",
            items: [
                ("type", "live"),
                ("game_id", gameID),
                ("first", String(first)),
                ("after", after)
            ],
            token: token
        )
    }

    public func followedStreams(userID: String, first: Int = 100, after: String? = nil, token: String) -> HTTPRequest {
        get(
            "streams/followed",
            items: [
                ("user_id", userID),
                ("first", String(first)),
                ("after", after)
            ],
            token: token
        )
    }

    public func streamsByUserIDs(_ ids: [String], token: String) -> HTTPRequest {
        get("streams", items: [("type", "live")] + ids.map { ("user_id", $0) }, token: token)
    }

    public func topGames(first: Int = 20, after: String? = nil, token: String) -> HTTPRequest {
        get(
            "games/top",
            items: [
                ("first", String(first)),
                ("after", after)
            ],
            token: token
        )
    }

    public func searchCategories(query: String, first: Int = 20, after: String? = nil, token: String) -> HTTPRequest {
        get(
            "search/categories",
            items: [
                ("query", query),
                ("first", String(first)),
                ("after", after)
            ],
            token: token
        )
    }

    public func searchChannels(query: String, liveOnly: Bool = false, first: Int = 20, after: String? = nil, token: String) -> HTTPRequest {
        get(
            "search/channels",
            items: [
                ("query", query),
                ("live_only", liveOnly ? "true" : "false"),
                ("first", String(first)),
                ("after", after)
            ],
            token: token
        )
    }

    public func usersByLogins(_ logins: [String], token: String) -> HTTPRequest {
        get("users", items: logins.map { ("login", $0) }, token: token)
    }

    public func usersByIDs(_ ids: [String], token: String) -> HTTPRequest {
        get("users", items: ids.map { ("id", $0) }, token: token)
    }

    public func channelInformation(broadcasterID: String, token: String) -> HTTPRequest {
        get("channels", items: [("broadcaster_id", broadcasterID)], token: token)
    }

    public func videos(userID: String, first: Int = 20, after: String? = nil, token: String) -> HTTPRequest {
        get(
            "videos",
            items: [
                ("user_id", userID),
                ("first", String(first)),
                ("after", after)
            ],
            token: token
        )
    }

    public func clips(broadcasterID: String, first: Int = 20, after: String? = nil, token: String) -> HTTPRequest {
        get(
            "clips",
            items: [
                ("broadcaster_id", broadcasterID),
                ("first", String(first)),
                ("after", after)
            ],
            token: token
        )
    }

    public func followedChannels(userID: String, first: Int = 100, after: String? = nil, token: String) -> HTTPRequest {
        get(
            "channels/followed",
            items: [
                ("user_id", userID),
                ("first", String(first)),
                ("after", after)
            ],
            token: token
        )
    }

    public func schedule(broadcasterID: String, first: Int = 25, after: String? = nil, token: String) -> HTTPRequest {
        get(
            "schedule",
            items: [
                ("broadcaster_id", broadcasterID),
                ("first", String(first)),
                ("after", after)
            ],
            token: token
        )
    }

    public func globalEmotes(token: String) -> HTTPRequest {
        get("chat/emotes/global", items: [], token: token)
    }

    public func channelEmotes(broadcasterID: String, token: String) -> HTTPRequest {
        get("chat/emotes", items: [("broadcaster_id", broadcasterID)], token: token)
    }

    public func globalBadges(token: String) -> HTTPRequest {
        get("chat/badges/global", items: [], token: token)
    }

    public func channelBadges(broadcasterID: String, token: String) -> HTTPRequest {
        get("chat/badges", items: [("broadcaster_id", broadcasterID)], token: token)
    }

    public func chatSettings(broadcasterID: String, moderatorID: String? = nil, token: String) -> HTTPRequest {
        get(
            "chat/settings",
            items: [
                ("broadcaster_id", broadcasterID),
                ("moderator_id", moderatorID)
            ],
            token: token
        )
    }

    public func sendChatMessage(broadcasterID: String, senderID: String, message: String, replyParentMessageID: String? = nil, token: String) -> HTTPRequest {
        var payload: [String: String] = [
            "broadcaster_id": broadcasterID,
            "sender_id": senderID,
            "message": message
        ]
        if let replyParentMessageID { payload["reply_parent_message_id"] = replyParentMessageID }
        return post("chat/messages", items: [], body: payload, token: token)
    }

    public func banUser(broadcasterID: String, moderatorID: String, userID: String, duration: Int? = nil, reason: String? = nil, token: String) -> HTTPRequest {
        var inner: [AnyJSON] = [.init("user_id", userID)]
        if let duration { inner.append(.init("duration", duration)) }
        if let reason { inner.append(.init("reason", reason)) }
        let body = JSONObject([.init("data", JSONObject(inner))])
        return post(
            "moderation/bans",
            items: [
                ("broadcaster_id", broadcasterID),
                ("moderator_id", moderatorID)
            ],
            jsonBody: body,
            token: token
        )
    }

    public func unbanUser(broadcasterID: String, moderatorID: String, userID: String, token: String) -> HTTPRequest {
        delete(
            "moderation/bans",
            items: [
                ("broadcaster_id", broadcasterID),
                ("moderator_id", moderatorID),
                ("user_id", userID)
            ],
            token: token
        )
    }

    public func deleteMessage(broadcasterID: String, moderatorID: String, messageID: String? = nil, token: String) -> HTTPRequest {
        delete(
            "chat/messages",
            items: [
                ("broadcaster_id", broadcasterID),
                ("moderator_id", moderatorID),
                ("message_id", messageID)
            ],
            token: token
        )
    }

    private func get(_ path: String, items: [(String, String?)], token: String?) -> HTTPRequest {
        HTTPRequest(method: .get, url: makeURL(path, items: items), headers: headers(token: token))
    }

    private func post(_ path: String, items: [(String, String?)], body: [String: String], token: String?) -> HTTPRequest {
        var requestHeaders = headers(token: token)
        requestHeaders["Content-Type"] = "application/json"
        let data = try? TwitchJSON.encoder.encode(body)
        return HTTPRequest(method: .post, url: makeURL(path, items: items), headers: requestHeaders, body: data)
    }

    private func post(_ path: String, items: [(String, String?)], jsonBody: JSONObject, token: String?) -> HTTPRequest {
        var requestHeaders = headers(token: token)
        requestHeaders["Content-Type"] = "application/json"
        return HTTPRequest(method: .post, url: makeURL(path, items: items), headers: requestHeaders, body: jsonBody.encoded())
    }

    private func delete(_ path: String, items: [(String, String?)], token: String?) -> HTTPRequest {
        HTTPRequest(method: .delete, url: makeURL(path, items: items), headers: headers(token: token))
    }

    private func makeURL(_ path: String, items: [(String, String?)]) -> URL {
        let base = baseURL.appendingPathComponent(path)
        return QueryEncoder.url(base.absoluteString, items: items) ?? base
    }

    private func headers(token: String?) -> [String: String] {
        var result = ["Client-Id": clientID]
        if let token { result["Authorization"] = "Bearer \(token)" }
        return result
    }
}

struct AnyJSON: Sendable {
    let key: String
    let value: JSONValue

    init(_ key: String, _ value: String) {
        self.key = key
        self.value = .string(value)
    }

    init(_ key: String, _ value: Int) {
        self.key = key
        self.value = .int(value)
    }

    init(_ key: String, _ value: JSONObject) {
        self.key = key
        self.value = .object(value)
    }
}

enum JSONValue: Sendable {
    case string(String)
    case int(Int)
    case object(JSONObject)

    func serialized() -> Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .object(let object): return object.dictionary()
        }
    }
}

struct JSONObject: Sendable {
    let entries: [AnyJSON]

    init(_ entries: [AnyJSON]) {
        self.entries = entries
    }

    func dictionary() -> [String: Any] {
        var result: [String: Any] = [:]
        for entry in entries { result[entry.key] = entry.value.serialized() }
        return result
    }

    func encoded() -> Data? {
        try? JSONSerialization.data(withJSONObject: dictionary(), options: [.sortedKeys])
    }
}
