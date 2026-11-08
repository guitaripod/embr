import Foundation

/// What Studio can be allowed to do, each tied to the Twitch permissions it needs. The streamer picks these before the
/// sign-in code appears, and only the picked ones are asked for, as Twitch's developer agreement requires.
public enum StudioFeature: String, CaseIterable, Sendable, Codable {
    case chat
    case followers
    case support
    case adBreaks
    case runAds
    case pollsAndPredictions
    case hypeTrainsAndGoals
    case channelPoints
    case moderation

    /// The scopes this feature asks Twitch for.
    public var scopes: [String] {
        switch self {
        case .chat: ["user:read:chat", "user:write:chat", "user:read:blocked_users", "user:manage:blocked_users"]
        case .followers: ["moderator:read:followers"]
        case .support: ["bits:read", "channel:read:subscriptions"]
        case .adBreaks: ["channel:read:ads", "channel:manage:ads"]
        case .runAds: ["channel:edit:commercial"]
        case .pollsAndPredictions: ["channel:read:polls", "channel:read:predictions"]
        case .hypeTrainsAndGoals: ["channel:read:hype_train", "channel:read:goals"]
        case .channelPoints: ["channel:read:redemptions"]
        case .moderation: [
            "moderator:manage:chat_messages", "moderator:manage:banned_users", "moderator:manage:chat_settings",
            "moderator:manage:shield_mode", "moderator:read:shield_mode", "moderator:manage:shoutouts",
            "moderator:manage:automod", "moderator:manage:unban_requests", "user:read:moderated_channels",
        ]
        }
    }

    /// Features that only work with the channel owner's own token: a moderator signed in for someone else's channel
    /// never gets them.
    public var isBroadcasterOnly: Bool {
        switch self {
        case .support, .adBreaks, .runAds, .pollsAndPredictions, .hypeTrainsAndGoals, .channelPoints: true
        case .chat, .followers, .moderation: false
        }
    }

    /// Chat is always on: it is what Studio is built around.
    public var isRequired: Bool { self == .chat }

    /// The scopes for a set of features, without duplicates, in a stable order.
    public static func scopes(for features: Set<StudioFeature>) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for feature in allCases where features.contains(feature) || feature.isRequired {
            for scope in feature.scopes where seen.insert(scope).inserted {
                result.append(scope)
            }
        }
        return result
    }

    /// The features a token's granted scopes cover in full.
    public static func granted(by scopes: [String]) -> Set<StudioFeature> {
        let granted = Set(scopes)
        return Set(allCases.filter { Set($0.scopes).isSubset(of: granted) })
    }
}

/// Whose channel Studio watches: the signed-in streamer's own, or one they moderate.
public enum StudioRole: Sendable, Equatable, Codable {
    case broadcaster
    case moderator
}

/// The EventSub subscriptions Studio adds to a channel's chat subscriptions, for one role and the features its token
/// carries. Each feature's subscriptions are made only when its scopes were granted, so a declined permission costs a
/// card, never a failed subscription.
public enum StudioSubscriptionPlan {
    public static func requests(
        role: StudioRole,
        features: Set<StudioFeature>,
        broadcasterID: String,
        userID: String,
        sessionID: String
    ) -> [EventSubSubscriptionRequest] {
        let transport = EventSubSubscriptionRequest.Transport(sessionID: sessionID)
        let channel = ["broadcaster_user_id": broadcasterID]
        let moderated = ["broadcaster_user_id": broadcasterID, "moderator_user_id": userID]
        func make(_ type: String, _ version: String, _ condition: [String: String]) -> EventSubSubscriptionRequest {
            EventSubSubscriptionRequest(type: type, version: version, condition: condition, transport: transport)
        }
        var requests = [
            make("stream.online", "1", channel),
            make("stream.offline", "1", channel),
            make("channel.update", "2", channel),
            make("channel.shared_chat.begin", "1", channel),
            make("channel.shared_chat.update", "1", channel),
            make("channel.shared_chat.end", "1", channel),
        ]
        if features.contains(.followers) {
            requests.append(make("channel.follow", "2", moderated))
        }
        if features.contains(.moderation) {
            requests.append(make("channel.shield_mode.begin", "1", moderated))
            requests.append(make("channel.shield_mode.end", "1", moderated))
        }
        guard role == .broadcaster else { return requests }
        if features.contains(.support) {
            requests.append(make("channel.bits.use", "1", channel))
        }
        if features.contains(.adBreaks) {
            requests.append(make("channel.ad_break.begin", "1", channel))
        }
        if features.contains(.pollsAndPredictions) {
            requests += ["channel.poll.begin", "channel.poll.progress", "channel.poll.end"].map { make($0, "1", channel) }
            requests += ["channel.prediction.begin", "channel.prediction.progress", "channel.prediction.lock", "channel.prediction.end"].map { make($0, "1", channel) }
        }
        if features.contains(.hypeTrainsAndGoals) {
            requests += ["channel.hype_train.begin", "channel.hype_train.progress", "channel.hype_train.end"].map { make($0, "2", channel) }
            requests += ["channel.goal.begin", "channel.goal.progress", "channel.goal.end"].map { make($0, "1", channel) }
        }
        if features.contains(.channelPoints) {
            requests.append(make("channel.channel_points_custom_reward_redemption.add", "1", channel))
        }
        return requests
    }
}
