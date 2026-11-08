import Foundation

/// The Helix requests Studio makes for the streamer's own channel, or one they moderate.
extension HelixRequestFactory {
    public func adSchedule(broadcasterID: String, token: String) -> HTTPRequest {
        get("channels/ads", items: [("broadcaster_id", broadcasterID)], token: token)
    }

    public func snoozeNextAd(broadcasterID: String, token: String) -> HTTPRequest {
        HTTPRequest(method: .post, url: makeURL("channels/ads/schedule/snooze", items: [("broadcaster_id", broadcasterID)]), headers: headers(token: token))
    }

    public func startCommercial(broadcasterID: String, length: Int, token: String) -> HTTPRequest {
        post(
            "channels/commercial",
            items: [],
            jsonBody: JSONObject([AnyJSON("broadcaster_id", broadcasterID), AnyJSON("length", min(max(length, 1), 180))]),
            token: token
        )
    }

    public func hypeTrainStatus(broadcasterID: String, token: String) -> HTTPRequest {
        get("hypetrain/status", items: [("broadcaster_id", broadcasterID)], token: token)
    }

    public func polls(broadcasterID: String, token: String) -> HTTPRequest {
        get("polls", items: [("broadcaster_id", broadcasterID), ("first", "1")], token: token)
    }

    public func predictions(broadcasterID: String, token: String) -> HTTPRequest {
        get("predictions", items: [("broadcaster_id", broadcasterID), ("first", "1")], token: token)
    }

    public func creatorGoals(broadcasterID: String, token: String) -> HTTPRequest {
        get("goals", items: [("broadcaster_id", broadcasterID)], token: token)
    }

    public func channelFollowers(broadcasterID: String, first: Int = 20, token: String) -> HTTPRequest {
        get("channels/followers", items: [("broadcaster_id", broadcasterID), ("first", String(min(max(first, 1), 100)))], token: token)
    }

    public func shoutout(fromBroadcasterID: String, toBroadcasterID: String, moderatorID: String, token: String) -> HTTPRequest {
        HTTPRequest(
            method: .post,
            url: makeURL("chat/shoutouts", items: [
                ("from_broadcaster_id", fromBroadcasterID),
                ("to_broadcaster_id", toBroadcasterID),
                ("moderator_id", moderatorID),
            ]),
            headers: headers(token: token)
        )
    }

    public func pinMessage(broadcasterID: String, moderatorID: String, messageID: String, durationSeconds: Int?, token: String) -> HTTPRequest {
        HTTPRequest(
            method: .put,
            url: makeURL("chat/pins", items: [
                ("broadcaster_id", broadcasterID),
                ("moderator_id", moderatorID),
                ("message_id", messageID),
                ("duration_seconds", durationSeconds.map { String(min(max($0, 30), 1800)) }),
            ]),
            headers: headers(token: token)
        )
    }

    /// Changes the chat modes. Only the modes given change; Twitch keeps the rest as they are.
    public func updateChatSettings(broadcasterID: String, moderatorID: String, change: ChatModeChange, token: String) -> HTTPRequest {
        var requestHeaders = headers(token: token)
        requestHeaders["Content-Type"] = "application/json"
        return HTTPRequest(
            method: .patch,
            url: makeURL("chat/settings", items: [("broadcaster_id", broadcasterID), ("moderator_id", moderatorID)]),
            headers: requestHeaders,
            body: change.body()
        )
    }

    public func shieldMode(broadcasterID: String, moderatorID: String, active: Bool, token: String) -> HTTPRequest {
        var requestHeaders = headers(token: token)
        requestHeaders["Content-Type"] = "application/json"
        let body = try? JSONSerialization.data(withJSONObject: ["is_active": active])
        return HTTPRequest(
            method: .put,
            url: makeURL("moderation/shield_mode", items: [("broadcaster_id", broadcasterID), ("moderator_id", moderatorID)]),
            headers: requestHeaders,
            body: body
        )
    }

    public func shieldModeStatus(broadcasterID: String, moderatorID: String, token: String) -> HTTPRequest {
        get("moderation/shield_mode", items: [("broadcaster_id", broadcasterID), ("moderator_id", moderatorID)], token: token)
    }
}

/// One change to the chat modes, from the status line's Chat Modes menu.
public enum ChatModeChange: Sendable, Equatable {
    case emoteOnly(Bool)
    case followersOnly(minutes: Int?)
    case slow(seconds: Int?)
    case subscribersOnly(Bool)

    func body() -> Data? {
        var object: [String: Any] = [:]
        switch self {
        case .emoteOnly(let on):
            object["emote_mode"] = on
        case .followersOnly(let minutes):
            object["follower_mode"] = minutes != nil
            if let minutes { object["follower_mode_duration"] = minutes }
        case .slow(let seconds):
            object["slow_mode"] = seconds != nil
            if let seconds { object["slow_mode_wait_time"] = seconds }
        case .subscribersOnly(let on):
            object["subscriber_mode"] = on
        }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

/// A channel the signed-in user moderates.
public struct ModeratedChannel: Sendable, Equatable, Identifiable {
    public let id: String
    public let login: String
    public let name: String

    public init(id: String, login: String, name: String) {
        self.id = id
        self.login = login
        self.name = name
    }
}

/// What Twitch said to Start Commercial.
public struct CommercialResult: Sendable, Equatable {
    public let length: Int
    public let retryAfter: TimeInterval
    public let message: String

    public init(length: Int, retryAfter: TimeInterval, message: String) {
        self.length = length
        self.retryAfter = retryAfter
        self.message = message
    }
}

/// Reads the answers to Studio's Helix requests. Each returns nil or an empty list for an answer it can't read, so a
/// change on Twitch's side costs one card, never the screen.
public enum StudioHelixDecoder {
    public static func adSchedule(_ data: Data, fetchedAt: Date) -> AdSchedule? {
        guard let item = first(data) else { return nil }
        return AdSchedule(
            nextAdAt: item.date("next_ad_at"),
            lastAdAt: item.date("last_ad_at"),
            duration: TimeInterval(item.int("duration") ?? 0),
            prerollFreeSeconds: TimeInterval(item.int("preroll_free_time") ?? 0),
            snoozeCount: item.int("snooze_count") ?? 0,
            snoozeRefreshAt: item.date("snooze_refresh_at"),
            fetchedAt: fetchedAt
        )
    }

    /// A snooze answers with only part of the schedule; the rest carries over from the one before it.
    public static func snoozed(_ data: Data, previous: AdSchedule?, fetchedAt: Date) -> AdSchedule? {
        guard let item = first(data) else { return nil }
        return AdSchedule(
            nextAdAt: item.date("next_ad_at") ?? previous?.nextAdAt,
            lastAdAt: previous?.lastAdAt,
            duration: previous?.duration ?? 0,
            prerollFreeSeconds: previous?.prerollFreeSeconds ?? 0,
            snoozeCount: item.int("snooze_count") ?? max((previous?.snoozeCount ?? 1) - 1, 0),
            snoozeRefreshAt: item.date("snooze_refresh_at") ?? previous?.snoozeRefreshAt,
            fetchedAt: fetchedAt
        )
    }

    public static func commercial(_ data: Data) -> CommercialResult? {
        guard let item = first(data) else { return nil }
        return CommercialResult(
            length: item.int("length") ?? 0,
            retryAfter: TimeInterval(item.int("retry_after") ?? 0),
            message: item.string("message") ?? ""
        )
    }

    public static func hypeTrain(_ data: Data) -> StudioHypeTrain? {
        guard let current = first(data)?.child("current") else { return nil }
        return StudioEventDecoder.hypeTrain(current, phase: .running)
    }

    public static func activePoll(_ data: Data) -> StudioPoll? {
        guard let item = first(data), item.string("status") == "ACTIVE" else { return nil }
        return StudioEventDecoder.poll(item, phase: .open)
    }

    public static func activePrediction(_ data: Data) -> StudioPrediction? {
        guard let item = first(data) else { return nil }
        switch item.string("status") {
        case "ACTIVE": return StudioEventDecoder.prediction(item, phase: .open)
        case "LOCKED": return StudioEventDecoder.prediction(item, phase: .locked)
        default: return nil
        }
    }

    public static func goals(_ data: Data) -> [StudioGoal] {
        list(data).map { StudioEventDecoder.goal($0, ended: false) }
    }

    public static func followers(_ data: Data) -> (total: Int, recent: [StudioFollow]) {
        let root = StudioJSON(data: data)
        let recent = list(data).compactMap { item -> StudioFollow? in
            guard let id = item.text("user_id") else { return nil }
            return StudioFollow(userID: id, userName: item.string("user_name") ?? item.string("user_login") ?? "", followedAt: item.date("followed_at") ?? Date())
        }
        return (root?.int("total") ?? recent.count, recent)
    }

    public static func moderatedChannels(_ data: Data) -> (channels: [ModeratedChannel], cursor: String?) {
        let channels = list(data).compactMap { item -> ModeratedChannel? in
            guard let id = item.text("broadcaster_id") else { return nil }
            let login = item.string("broadcaster_login") ?? ""
            return ModeratedChannel(id: id, login: login, name: item.text("broadcaster_name") ?? login)
        }
        let cursor = StudioJSON(data: data)?.child("pagination")?.text("cursor")
        return (channels, cursor)
    }

    public static func shieldModeActive(_ data: Data) -> Bool? {
        first(data)?.bool("is_active")
    }

    private static func list(_ data: Data) -> [StudioJSON] {
        StudioJSON(data: data)?.children("data") ?? []
    }

    private static func first(_ data: Data) -> StudioJSON? {
        list(data).first
    }
}
