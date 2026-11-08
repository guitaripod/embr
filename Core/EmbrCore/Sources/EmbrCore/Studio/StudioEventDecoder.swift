import Foundation

/// Turns EventSub notifications into Studio events. Chat notifications carry subs, gifts and raids; a cheer is read from
/// the chat message that carries it; the rest have subscription types of their own. Anything that belongs to another
/// channel of a shared chat session is left out: Studio's alerts are for the streamer's own channel.
public enum StudioEventDecoder {
    /// Every subscription type Studio reads, besides the chat types the chat engine already subscribes to.
    public static let studioTypes: Set<String> = [
        "channel.follow", "channel.bits.use", "channel.channel_points_custom_reward_redemption.add",
        "channel.hype_train.begin", "channel.hype_train.progress", "channel.hype_train.end",
        "channel.poll.begin", "channel.poll.progress", "channel.poll.end",
        "channel.prediction.begin", "channel.prediction.progress", "channel.prediction.lock", "channel.prediction.end",
        "channel.goal.begin", "channel.goal.progress", "channel.goal.end",
        "channel.ad_break.begin", "stream.online", "stream.offline", "channel.update",
        "channel.shared_chat.begin", "channel.shared_chat.update", "channel.shared_chat.end",
        "channel.shield_mode.begin", "channel.shield_mode.end",
    ]

    /// The chat types that also feed Studio: notices for subs, gifts and raids, and messages for cheers.
    public static let chatTypes: Set<String> = ["channel.chat.notification", "channel.chat.message"]

    public static func reads(_ subscriptionType: String) -> Bool {
        studioTypes.contains(subscriptionType) || chatTypes.contains(subscriptionType)
    }

    /// The Studio events in one notification, or none when it carries nothing Studio shows.
    public static func events(subscriptionType: String, eventData: Data, receivedAt: Date = Date()) -> [StudioEvent] {
        guard let json = StudioJSON(data: eventData) else { return [] }
        switch subscriptionType {
        case "channel.chat.notification": return notification(json).map { [$0] } ?? []
        case "channel.chat.message": return cheer(json).map { [$0] } ?? []
        case "channel.follow": return follow(json, receivedAt: receivedAt).map { [$0] } ?? []
        case "channel.bits.use": return powerUp(json).map { [$0] } ?? []
        case "channel.channel_points_custom_reward_redemption.add": return redemption(json).map { [$0] } ?? []
        case "channel.hype_train.begin", "channel.hype_train.progress": return [.hypeTrain(hypeTrain(json, phase: .running))]
        case "channel.hype_train.end": return [.hypeTrain(hypeTrain(json, phase: .ended))]
        case "channel.poll.begin", "channel.poll.progress": return [.poll(poll(json, phase: .open))]
        case "channel.poll.end": return [.poll(poll(json, phase: .ended))]
        case "channel.prediction.begin", "channel.prediction.progress": return [.prediction(prediction(json, phase: .open))]
        case "channel.prediction.lock": return [.prediction(prediction(json, phase: .locked))]
        case "channel.prediction.end": return [.prediction(prediction(json, phase: predictionEnd(json)))]
        case "channel.goal.begin", "channel.goal.progress": return [.goal(goal(json, ended: false))]
        case "channel.goal.end": return [.goal(goal(json, ended: true))]
        case "channel.ad_break.begin": return [.adBreakBegan(adBreak(json, receivedAt: receivedAt))]
        case "stream.online": return [.streamOnline(startedAt: json.date("started_at") ?? receivedAt)]
        case "stream.offline": return [.streamOffline]
        case "channel.update": return [.channelUpdated(title: json.string("title") ?? "", categoryName: json.string("category_name") ?? "")]
        case "channel.shared_chat.begin", "channel.shared_chat.update": return [.sharedChat(sharedChat(json))]
        case "channel.shared_chat.end": return [.sharedChat(nil)]
        case "channel.shield_mode.begin": return [.shieldMode(active: true)]
        case "channel.shield_mode.end": return [.shieldMode(active: false)]
        default: return []
        }
    }

    private static func notification(_ json: StudioJSON) -> StudioEvent? {
        if json.text("source_broadcaster_user_id").map({ $0 != json.string("broadcaster_user_id") }) ?? false { return nil }
        let id = json.string("message_id") ?? UUID().uuidString
        let anonymous = json.bool("chatter_is_anonymous") ?? false
        let userID = anonymous ? "" : json.string("chatter_user_id") ?? ""
        let userName = anonymous ? "" : json.string("chatter_user_name") ?? json.string("chatter_user_login") ?? ""
        let message = json.child("message")?.string("text") ?? ""
        switch json.string("notice_type") {
        case "sub":
            let sub = json.child("sub")
            return .subscription(StudioSubscription(
                id: id, userID: userID, userName: userName, kind: .new,
                tier: tier(sub?.string("sub_tier")), isPrime: sub?.bool("is_prime") ?? false, message: message
            ))
        case "resub":
            let resub = json.child("resub")
            return .subscription(StudioSubscription(
                id: id, userID: userID, userName: userName, kind: .resub(months: resub?.int("cumulative_months") ?? 0),
                tier: tier(resub?.string("sub_tier")), isPrime: resub?.bool("is_prime") ?? false, message: message
            ))
        case "sub_gift":
            let gift = json.child("sub_gift")
            guard gift?.text("community_gift_id") == nil else { return nil }
            return .subscription(StudioSubscription(
                id: id, userID: userID, userName: userName,
                kind: .gift(recipientName: gift?.string("recipient_user_name") ?? gift?.string("recipient_user_login") ?? ""),
                tier: tier(gift?.string("sub_tier")), isPrime: false, message: message
            ))
        case "community_sub_gift":
            let bomb = json.child("community_sub_gift")
            return .giftBomb(StudioGiftBomb(
                id: bomb?.string("id") ?? id,
                gifterID: anonymous ? nil : userID,
                gifterName: anonymous ? nil : userName,
                count: bomb?.int("total") ?? 1,
                tier: tier(bomb?.string("sub_tier"))
            ))
        case "gift_paid_upgrade":
            return .subscription(StudioSubscription(id: id, userID: userID, userName: userName, kind: .giftUpgrade, tier: .one, isPrime: false, message: message))
        case "prime_paid_upgrade":
            let upgrade = json.child("prime_paid_upgrade")
            return .subscription(StudioSubscription(
                id: id, userID: userID, userName: userName, kind: .primeUpgrade,
                tier: tier(upgrade?.string("sub_tier")), isPrime: false, message: message
            ))
        case "pay_it_forward":
            return .subscription(StudioSubscription(id: id, userID: userID, userName: userName, kind: .payItForward, tier: .one, isPrime: false, message: message))
        case "raid":
            guard let raid = json.child("raid") else { return nil }
            return .raid(StudioRaid(
                raiderID: raid.string("user_id") ?? userID,
                raiderName: raid.string("user_name") ?? userName,
                raiderLogin: raid.string("user_login") ?? "",
                viewers: raid.int("viewer_count") ?? 0,
                profileImageURL: raid.text("profile_image_url").flatMap(URL.init(string:))
            ))
        case "charity_donation":
            guard let charity = json.child("charity_donation"), let amount = charity.child("amount") else { return nil }
            return .charity(StudioCharityDonation(
                userID: userID, userName: userName,
                charityName: charity.string("charity_name") ?? "",
                minorUnits: amount.int("value") ?? 0,
                decimalPlaces: amount.int("decimal_place") ?? 2,
                currency: amount.string("currency") ?? ""
            ))
        default:
            return nil
        }
    }

    private static func cheer(_ json: StudioJSON) -> StudioEvent? {
        guard let bits = json.child("cheer")?.int("bits"), bits > 0 else { return nil }
        if let source = json.text("source_broadcaster_user_id"), source != json.string("broadcaster_user_id") { return nil }
        let anonymous = json.string("chatter_user_login") == "ananonymouscheerer"
        return .cheer(StudioCheer(
            id: json.string("message_id") ?? UUID().uuidString,
            userID: anonymous ? nil : json.string("chatter_user_id"),
            userName: anonymous ? nil : json.string("chatter_user_name"),
            bits: bits,
            message: json.child("message")?.string("text") ?? ""
        ))
    }

    private static func follow(_ json: StudioJSON, receivedAt: Date) -> StudioEvent? {
        guard let userID = json.text("user_id") else { return nil }
        return .follow(StudioFollow(
            userID: userID,
            userName: json.string("user_name") ?? json.string("user_login") ?? "",
            followedAt: json.date("followed_at") ?? receivedAt
        ))
    }

    /// Power-ups only: plain cheers come with their chat message, which also carries what the cheerer wrote.
    private static func powerUp(_ json: StudioJSON) -> StudioEvent? {
        guard let kind = json.string("type"), kind != "cheer" else { return nil }
        let title = json.child("custom_power_up")?.text("title")
            ?? json.child("power_up")?.text("type").map(powerUpName)
            ?? "Power-up"
        return .powerUp(StudioPowerUp(
            userID: json.string("user_id") ?? "",
            userName: json.string("user_name") ?? json.string("user_login") ?? "",
            bits: json.int("bits") ?? 0,
            title: title
        ))
    }

    private static func powerUpName(_ type: String) -> String {
        switch type {
        case "message_effect": "Message Effect"
        case "celebration": "On-Screen Celebration"
        case "gigantify_an_emote": "Gigantify an Emote"
        default: type
        }
    }

    private static func redemption(_ json: StudioJSON) -> StudioEvent? {
        guard let reward = json.child("reward") else { return nil }
        return .redemption(StudioRedemption(
            id: json.string("id") ?? UUID().uuidString,
            userID: json.string("user_id") ?? "",
            userName: json.string("user_name") ?? json.string("user_login") ?? "",
            rewardTitle: reward.string("title") ?? "",
            cost: reward.int("cost") ?? 0,
            input: json.string("user_input") ?? ""
        ))
    }

    static func hypeTrain(_ json: StudioJSON, phase: StudioHypeTrain.Phase) -> StudioHypeTrain {
        StudioHypeTrain(
            id: json.string("id") ?? "",
            phase: phase,
            level: json.int("level") ?? 1,
            progress: json.int("progress") ?? 0,
            goal: json.int("goal") ?? 0,
            total: json.int("total") ?? 0,
            expiresAt: phase == .running ? json.date("expires_at") : nil,
            topContributors: json.children("top_contributions").map {
                StudioContributor(
                    userName: $0.string("user_name") ?? $0.string("user_login") ?? "",
                    kind: StudioContributor.Kind(rawValue: $0.string("type") ?? "") ?? .other,
                    total: $0.int("total") ?? 0
                )
            },
            isGolden: json.string("type") == "golden_kappa"
        )
    }

    static func poll(_ json: StudioJSON, phase: StudioPoll.Phase) -> StudioPoll {
        StudioPoll(
            id: json.string("id") ?? "",
            title: json.string("title") ?? "",
            choices: json.children("choices").map {
                StudioChoice(id: $0.string("id") ?? "", title: $0.string("title") ?? "", votes: $0.int("votes") ?? 0)
            },
            endsAt: json.date("ends_at"),
            phase: phase
        )
    }

    static func prediction(_ json: StudioJSON, phase: StudioPrediction.Phase) -> StudioPrediction {
        StudioPrediction(
            id: json.string("id") ?? "",
            title: json.string("title") ?? "",
            outcomes: json.children("outcomes").map {
                StudioChoice(id: $0.string("id") ?? "", title: $0.string("title") ?? "", votes: $0.int("channel_points") ?? 0)
            },
            locksAt: json.date("locks_at"),
            phase: phase
        )
    }

    private static func predictionEnd(_ json: StudioJSON) -> StudioPrediction.Phase {
        json.string("status") == "canceled" ? .canceled : .resolved(winningOutcomeID: json.text("winning_outcome_id"))
    }

    static func goal(_ json: StudioJSON, ended: Bool) -> StudioGoal {
        StudioGoal(
            id: json.string("id") ?? "",
            kind: json.string("type") ?? "",
            description: json.string("description") ?? "",
            current: json.int("current_amount") ?? 0,
            target: json.int("target_amount") ?? 0,
            ended: ended,
            achieved: json.bool("is_achieved") ?? false
        )
    }

    private static func adBreak(_ json: StudioJSON, receivedAt: Date) -> StudioAdBreak {
        StudioAdBreak(
            startedAt: json.date("started_at") ?? receivedAt,
            duration: TimeInterval(json.int("duration_seconds") ?? 0),
            isAutomatic: json.bool("is_automatic") ?? false
        )
    }

    private static func sharedChat(_ json: StudioJSON) -> StudioSharedChat {
        let own = json.string("broadcaster_user_id")
        return StudioSharedChat(
            sessionID: json.string("session_id") ?? "",
            participants: json.children("participants")
                .filter { $0.string("broadcaster_user_id") != own }
                .map { $0.string("broadcaster_user_name") ?? $0.string("broadcaster_user_login") ?? "" }
        )
    }

    private static func tier(_ raw: String?) -> StudioTier {
        raw.flatMap(StudioTier.init(rawValue:)) ?? .one
    }
}
