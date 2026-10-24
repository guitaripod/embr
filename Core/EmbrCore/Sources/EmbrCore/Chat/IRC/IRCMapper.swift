import Foundation

public enum IRCMapper {
    public static func chatMessage(from msg: IRCMessage, channelID: String) -> ChatMessage? {
        switch msg.command.uppercased() {
        case "PRIVMSG", "USERNOTICE":
            break
        default:
            return nil
        }

        let trailing = msg.parameters.count >= 2 ? msg.parameters[1] : (msg.parameters.last ?? "")
        let (rawText, isAction) = stripAction(trailing)

        let fragments = buildFragments(text: rawText, emotesTag: msg.tags["emotes"])

        let author = buildUser(from: msg)
        let badges = buildBadges(msg.tags["badges"])
        let reply = buildReply(from: msg.tags)
        let notice = buildNotice(from: msg)
        let messageType = resolveMessageType(from: msg.tags)
        let bits = msg.tags["bits"].flatMap { Int($0) }

        return ChatMessage(
            id: msg.tags["id"] ?? "",
            channelID: channelID,
            timestamp: timestamp(from: msg.tags["tmi-sent-ts"]),
            author: author,
            fragments: fragments,
            badges: badges,
            messageType: messageType,
            isAction: isAction,
            bits: bits,
            reply: reply,
            notice: notice
        )
    }

    private static func stripAction(_ text: String) -> (text: String, isAction: Bool) {
        let soh = "\u{1}"
        guard text.hasPrefix(soh + "ACTION ") && text.hasSuffix(soh) && text.count > 8 else {
            return (text, false)
        }
        let inner = text.dropFirst(8).dropLast()
        return (String(inner), true)
    }

    private static func buildFragments(text: String, emotesTag: String?) -> [ChatFragment] {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.isEmpty else { return [] }

        guard let emotesTag, !emotesTag.isEmpty else {
            return [.text(text)]
        }

        var ranges: [(start: Int, end: Int, id: String)] = []
        for group in emotesTag.split(separator: "/", omittingEmptySubsequences: true) {
            guard let colon = group.firstIndex(of: ":") else { continue }
            let id = String(group[group.startIndex..<colon])
            let spans = group[group.index(after: colon)...]
            for span in spans.split(separator: ",", omittingEmptySubsequences: true) {
                let bounds = span.split(separator: "-", omittingEmptySubsequences: true)
                guard bounds.count == 2,
                      let start = Int(bounds[0]),
                      let end = Int(bounds[1]),
                      start >= 0, end >= start, end < scalars.count else { continue }
                ranges.append((start, end, id))
            }
        }

        guard !ranges.isEmpty else { return [.text(text)] }
        ranges.sort { $0.start < $1.start }

        var fragments: [ChatFragment] = []
        var cursor = 0
        for range in ranges {
            if range.start < cursor { continue }
            if range.start > cursor {
                let slice = String(String.UnicodeScalarView(scalars[cursor..<range.start]))
                if !slice.isEmpty { fragments.append(.text(slice)) }
            }
            let emoteText = String(String.UnicodeScalarView(scalars[range.start...range.end]))
            fragments.append(.emote(TwitchEmoteRef(id: range.id, text: emoteText)))
            cursor = range.end + 1
        }
        if cursor < scalars.count {
            let slice = String(String.UnicodeScalarView(scalars[cursor..<scalars.count]))
            if !slice.isEmpty { fragments.append(.text(slice)) }
        }
        return fragments
    }

    private static func buildUser(from msg: IRCMessage) -> ChatUser {
        let login = msg.tags["login"].flatMap { $0.isEmpty ? nil : $0 } ?? msg.nickname ?? ""
        let display = msg.tags["display-name"].flatMap { $0.isEmpty ? nil : $0 } ?? login
        let color = msg.tags["color"].flatMap { $0.isEmpty ? nil : ChatColor(hex: $0) }
        return ChatUser(
            id: msg.tags["user-id"] ?? "",
            login: login,
            displayName: display,
            color: color
        )
    }

    private static func buildBadges(_ tag: String?) -> [MessageBadge] {
        guard let tag, !tag.isEmpty else { return [] }
        return tag.split(separator: ",", omittingEmptySubsequences: true).compactMap { entry in
            let parts = entry.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard let setID = parts.first, !setID.isEmpty else { return nil }
            let version = parts.count > 1 ? String(parts[1]) : ""
            return MessageBadge(setID: String(setID), id: version)
        }
    }

    private static func buildReply(from tags: [String: String]) -> ReplyContext? {
        guard let parentID = tags["reply-parent-msg-id"], !parentID.isEmpty else { return nil }
        return ReplyContext(
            parentMessageID: parentID,
            parentUserID: tags["reply-parent-user-id"] ?? "",
            parentLogin: tags["reply-parent-user-login"] ?? "",
            parentDisplayName: tags["reply-parent-display-name"] ?? "",
            parentText: tags["reply-parent-msg-body"] ?? "",
            threadParentMessageID: tags["reply-thread-parent-msg-id"]
        )
    }

    private static func buildNotice(from msg: IRCMessage) -> ChannelNotice? {
        guard msg.command.uppercased() == "USERNOTICE", let msgID = msg.tags["msg-id"] else { return nil }
        let system = msg.tags["system-msg"] ?? ""
        return ChannelNotice(kind: noticeKind(from: msgID), systemMessage: system)
    }

    private static func noticeKind(from msgID: String) -> NoticeKind {
        switch msgID {
        case "sub": return .sub
        case "resub": return .resub
        case "subgift": return .subGift
        case "submysterygift": return .communitySubGift
        case "giftpaidupgrade", "anongiftpaidupgrade": return .giftPaidUpgrade
        case "primepaidupgrade": return .primePaidUpgrade
        case "raid": return .raid
        case "unraid": return .unraid
        case "standardpayforward", "communitypayforward": return .payItForward
        case "announcement": return .announcement
        case "bitsbadgetier": return .bitsBadgeTier
        case "charitydonation": return .charityDonation
        default: return .other
        }
    }

    private static func resolveMessageType(from tags: [String: String]) -> MessageType {
        if tags["msg-id"] == "highlighted-message" { return .channelPointsHighlighted }
        if tags["msg-id"] == "skip-subs-mode-message" { return .channelPointsSubOnly }
        if tags["first-msg"] == "1" { return .userIntro }
        return .regular
    }

    private static func timestamp(from raw: String?) -> Date {
        guard let raw, let millis = Double(raw) else { return Date() }
        return Date(timeIntervalSince1970: millis / 1000)
    }
}
