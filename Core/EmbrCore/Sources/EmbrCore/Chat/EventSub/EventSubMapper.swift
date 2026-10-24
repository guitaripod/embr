import Foundation

public enum EventSubMapper {
    public static func chatMessage(fromEvent data: Data, timestamp: Date) throws -> ChatMessage {
        let event = try TwitchJSON.decode(ChatMessageEvent.self, from: data)
        return makeMessage(
            id: event.messageID,
            channelID: event.broadcasterUserID,
            timestamp: timestamp,
            chatterID: event.chatterUserID,
            chatterLogin: event.chatterUserLogin,
            chatterName: event.chatterUserName,
            color: event.color,
            body: event.message,
            badges: event.badges,
            messageType: mapMessageType(event.messageType),
            bits: event.cheer?.bits,
            reply: event.reply.map(makeReply),
            notice: nil,
            sharedSource: makeSharedSource(
                broadcasterID: event.sourceBroadcasterUserID,
                login: event.sourceBroadcasterUserLogin,
                name: event.sourceBroadcasterUserName,
                isSourceOnly: event.isSourceOnly
            )
        )
    }

    public static func notification(fromEvent data: Data, timestamp: Date) throws -> ChatMessage {
        let event = try TwitchJSON.decode(ChatNotificationEvent.self, from: data)
        let notice = ChannelNotice(
            kind: mapNoticeKind(event.noticeType),
            systemMessage: event.systemMessage
        )
        return makeMessage(
            id: event.messageID,
            channelID: event.broadcasterUserID,
            timestamp: timestamp,
            chatterID: event.chatterUserID,
            chatterLogin: event.chatterUserLogin,
            chatterName: event.chatterUserName,
            color: event.color,
            body: event.message,
            badges: event.badges,
            messageType: .regular,
            bits: nil,
            reply: nil,
            notice: notice,
            sharedSource: makeSharedSource(
                broadcasterID: event.sourceBroadcasterUserID,
                login: event.sourceBroadcasterUserLogin,
                name: event.sourceBroadcasterUserName,
                isSourceOnly: nil
            )
        )
    }

    public static func chatEvent(subscriptionType: String, eventData: Data, timestamp: Date) throws -> ChatEvent {
        switch subscriptionType {
        case "channel.chat.message":
            return .message(try chatMessage(fromEvent: eventData, timestamp: timestamp))
        case "channel.chat.notification":
            return .message(try notification(fromEvent: eventData, timestamp: timestamp))
        case "channel.chat.message_delete":
            let event = try TwitchJSON.decode(ChatMessageDeleteEvent.self, from: eventData)
            return .deleteMessage(messageID: event.messageID)
        case "channel.chat.clear_user_messages":
            let event = try TwitchJSON.decode(ChatClearUserMessagesEvent.self, from: eventData)
            return .clearUserMessages(userID: event.targetUserID, login: event.targetUserLogin)
        case "channel.chat.clear":
            _ = try TwitchJSON.decode(ChatClearEvent.self, from: eventData)
            return .clearChat
        default:
            throw APIError.decoding("Unsupported chat subscription type: \(subscriptionType)")
        }
    }

    private static func makeMessage(
        id: String,
        channelID: String,
        timestamp: Date,
        chatterID: String,
        chatterLogin: String,
        chatterName: String,
        color: String?,
        body: ChatMessageBody,
        badges: [ChatBadgePayload],
        messageType: MessageType,
        bits: Int?,
        reply: ReplyContext?,
        notice: ChannelNotice?,
        sharedSource: SharedChatSource?
    ) -> ChatMessage {
        let chatColor = color.flatMap { $0.isEmpty ? nil : ChatColor(hex: $0) }
        let author = ChatUser(
            id: chatterID,
            login: chatterLogin,
            displayName: chatterName,
            color: chatColor
        )
        let isAction = detectAction(body.text)
        return ChatMessage(
            id: id,
            channelID: channelID,
            timestamp: timestamp,
            author: author,
            fragments: body.fragments.compactMap(makeFragment),
            badges: badges.map(makeBadge),
            messageType: messageType,
            isAction: isAction,
            bits: bits,
            reply: reply,
            notice: notice,
            sharedChatSource: sharedSource
        )
    }

    private static func makeFragment(_ payload: ChatFragmentPayload) -> ChatFragment? {
        switch payload.type {
        case "text":
            return .text(payload.text)
        case "emote":
            guard let emote = payload.emote else { return .text(payload.text) }
            return .emote(TwitchEmoteRef(
                id: emote.id,
                text: payload.text,
                setID: emote.emoteSetID,
                ownerID: emote.ownerID,
                formats: mapFormats(emote.format)
            ))
        case "cheermote":
            guard let cheer = payload.cheermote else { return .text(payload.text) }
            return .cheermote(CheermoteRef(
                prefix: cheer.prefix,
                bits: cheer.bits,
                tier: cheer.tier,
                text: payload.text
            ))
        case "mention":
            guard let mention = payload.mention else { return .text(payload.text) }
            return .mention(MentionRef(
                userID: mention.userID,
                login: mention.userLogin,
                displayName: mention.userName
            ))
        default:
            return .text(payload.text)
        }
    }

    private static func mapFormats(_ raw: [String]) -> [EmoteFormat] {
        let mapped = raw.compactMap { value -> EmoteFormat? in
            switch value {
            case "static": return .static
            case "animated": return .animated
            default: return nil
            }
        }
        return mapped.isEmpty ? [.static] : mapped
    }

    private static func makeBadge(_ payload: ChatBadgePayload) -> MessageBadge {
        let info = payload.info.flatMap { $0.isEmpty ? nil : $0 }
        return MessageBadge(setID: payload.setID, id: payload.id, info: info)
    }

    private static func makeReply(_ payload: ChatReplyPayload) -> ReplyContext {
        ReplyContext(
            parentMessageID: payload.parentMessageID,
            parentUserID: payload.parentUserID,
            parentLogin: payload.parentUserLogin,
            parentDisplayName: payload.parentUserName,
            parentText: payload.parentMessageBody,
            threadParentMessageID: payload.threadMessageID
        )
    }

    private static func makeSharedSource(
        broadcasterID: String?,
        login: String?,
        name: String?,
        isSourceOnly: Bool?
    ) -> SharedChatSource? {
        guard let broadcasterID, let login, let name else { return nil }
        return SharedChatSource(
            broadcasterID: broadcasterID,
            broadcasterLogin: login,
            broadcasterName: name,
            isSourceOnly: isSourceOnly ?? false
        )
    }

    private static func detectAction(_ text: String) -> Bool {
        text.utf8.first == 0x01
    }

    private static func mapMessageType(_ raw: String) -> MessageType {
        switch raw {
        case "text": return .regular
        case "channel_points_highlighted": return .channelPointsHighlighted
        case "channel_points_sub_only": return .channelPointsSubOnly
        case "user_intro": return .userIntro
        case "power_ups_message_effect": return .powerUpsMessageEffect
        case "power_ups_gigantified_emote": return .powerUpsGigantifiedEmote
        default: return .regular
        }
    }

    private static func mapNoticeKind(_ raw: String) -> NoticeKind {
        switch raw {
        case "sub": return .sub
        case "resub": return .resub
        case "sub_gift": return .subGift
        case "community_sub_gift": return .communitySubGift
        case "gift_paid_upgrade": return .giftPaidUpgrade
        case "prime_paid_upgrade": return .primePaidUpgrade
        case "raid": return .raid
        case "unraid": return .unraid
        case "pay_it_forward": return .payItForward
        case "announcement": return .announcement
        case "bits_badge_tier": return .bitsBadgeTier
        case "charity_donation": return .charityDonation
        default: return .other
        }
    }
}
