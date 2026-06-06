import UIKit
import EmbrCore

protocol MessageLayoutSettings {
    var chatShowsTimestamps: Bool { get }
    var chatMessageFontSize: CGFloat { get }
    var chatPreferredEmoteScale: EmoteScale { get }
    var chatLineSpacing: CGFloat { get }
}

struct MessageLayout {
    private let width: CGFloat
    private let catalog: EmoteCatalog
    private let badges: BadgeCatalog
    private let showsTimestamps: Bool
    private let font: UIFont
    private let usernameFont: UIFont
    private let timestampFont: UIFont
    private let emoteScale: EmoteScale
    private let lineSpacing: CGFloat
    private let currentUserLogin: String?

    private let horizontalInset: CGFloat = 8
    private let verticalInset: CGFloat = 4
    private let badgeSpacing: CGFloat = 3
    private let emoteSidePadding: CGFloat = 1
    private let replyLineHeight: CGFloat = 16

    init(width: CGFloat, settings: Settings, catalog: EmoteCatalog, badges: BadgeCatalog, currentUserLogin: String? = nil) {
        let resolved: MessageLayoutSettings = settings
        let fontSize = resolved.chatMessageFontSize
        self.width = width
        self.catalog = catalog
        self.badges = badges
        self.showsTimestamps = resolved.chatShowsTimestamps
        self.emoteScale = resolved.chatPreferredEmoteScale
        self.lineSpacing = resolved.chatLineSpacing
        self.currentUserLogin = currentUserLogin
        self.font = .systemFont(ofSize: fontSize)
        self.usernameFont = .boldSystemFont(ofSize: fontSize)
        self.timestampFont = .monospacedDigitSystemFont(ofSize: fontSize - 2, weight: .regular)
    }

    func layout(_ message: ChatMessage) -> LaidOutMessage {
        let availableWidth = max(1, width - horizontalInset * 2)
        let replyHeight = message.reply != nil ? replyLineHeight + 2 : 0

        let resolvedBadges = badges.resolve(message: message)
        let badgeBox = lineHeight
        let badgePrefixWidth = resolvedBadges.isEmpty
            ? 0
            : CGFloat(resolvedBadges.count) * (badgeBox + badgeSpacing)

        let attributed = NSMutableAttributedString()
        var usernameRange = NSRange(location: 0, length: 0)

        if let notice = message.notice {
            attributed.append(NSAttributedString(string: noticeSymbol(notice.kind) + " " + notice.systemMessage, attributes: [
                .font: usernameFont,
                .foregroundColor: Theme.noticeColor(notice.kind),
            ]))
            if !message.fragments.isEmpty {
                attributed.append(NSAttributedString(string: "\n", attributes: [.font: font]))
            }
        }

        if showsTimestamps {
            let stamp = Self.timestampString(message.timestamp)
            attributed.append(NSAttributedString(string: stamp + " ", attributes: [
                .font: timestampFont,
                .foregroundColor: Theme.secondaryText,
            ]))
        }

        let showsAuthorLine = message.notice == nil || !message.fragments.isEmpty
        let usernameColor = Theme.readableUsernameColor(message.author.color)
        if showsAuthorLine {
            let usernameStart = attributed.length
            let separator = message.isAction ? " " : ": "
            attributed.append(NSAttributedString(string: message.author.displayName, attributes: [
                .font: usernameFont,
                .foregroundColor: usernameColor,
            ]))
            usernameRange = NSRange(location: usernameStart, length: attributed.length - usernameStart)
            attributed.append(NSAttributedString(string: separator, attributes: [
                .font: usernameFont,
                .foregroundColor: usernameColor,
            ]))
        }

        let bodyColor = message.isAction ? usernameColor : Theme.primaryText
        let cheerBits = message.bits ?? 0
        if cheerBits > 0 {
            attributed.append(NSAttributedString(string: "✦ \(Self.formatBits(cheerBits)) ", attributes: [
                .font: usernameFont,
                .foregroundColor: Theme.cheerColor(forBits: cheerBits),
            ]))
        }
        let tokens = MessageTokenizer.tokens(for: message, catalog: catalog)
        var emoteTokens: [(emote: Emote, attributedIndex: Int)] = []
        var links: [LaidOutMessage.LinkSpan] = []
        var mentionsCurrentUser = false

        for token in tokens {
            switch token {
            case .text(let value):
                attributed.append(NSAttributedString(string: value, attributes: [
                    .font: font,
                    .foregroundColor: bodyColor,
                ]))
            case .mention(let ref):
                if let login = currentUserLogin, ref.displayName.lowercased() == login.lowercased() {
                    mentionsCurrentUser = true
                }
                attributed.append(NSAttributedString(string: "@\(ref.displayName)", attributes: [
                    .font: usernameFont,
                    .foregroundColor: Theme.accent,
                ]))
            case .link(let url, let raw):
                let start = attributed.length
                attributed.append(NSAttributedString(string: raw, attributes: [
                    .font: font,
                    .foregroundColor: Theme.link,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ]))
                links.append(.init(range: NSRange(location: start, length: attributed.length - start), url: url))
            case .cheermote(let ref):
                attributed.append(NSAttributedString(string: ref.text, attributes: [
                    .font: usernameFont,
                    .foregroundColor: Theme.cheerColor(forBits: ref.bits),
                ]))
            case .emote(let emote):
                let index = attributed.length
                emoteTokens.append((emote, index))
                attributed.append(emotePlaceholder(for: emote))
            }
        }

        if !mentionsCurrentUser, let login = currentUserLogin {
            mentionsCurrentUser = message.plainText.lowercased().contains("@" + login.lowercased())
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        attributed.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: attributed.length))

        let textOriginX = horizontalInset + badgePrefixWidth
        let textWidth = max(1, availableWidth - badgePrefixWidth)
        let textOriginY = verticalInset + replyHeight

        let (textHeight, emotePlacements) = layoutText(
            attributed: attributed,
            emoteTokens: emoteTokens,
            textWidth: textWidth,
            originX: textOriginX,
            originY: textOriginY
        )

        let badgePlacements = resolveBadgePlacements(
            resolvedBadges,
            box: badgeBox,
            originY: textOriginY
        )

        let totalHeight = max(textHeight, lineHeight) + verticalInset * 2 + replyHeight
        let isHighlighted = message.messageType == .channelPointsHighlighted

        return LaidOutMessage(
            height: ceil(totalHeight),
            width: width,
            attributedText: attributed,
            textOrigin: CGPoint(x: textOriginX, y: textOriginY),
            emotePlacements: emotePlacements,
            badgePlacements: badgePlacements,
            usernameRange: usernameRange,
            links: links,
            textWidth: textWidth,
            replyHeight: replyHeight,
            isHighlighted: isHighlighted,
            mentionsCurrentUser: mentionsCurrentUser,
            isAnnouncement: message.notice?.kind == .announcement,
            isCheer: cheerBits > 0
        )
    }

    private static func formatBits(_ bits: Int) -> String {
        if bits >= 1000 { return String(format: "%.1fK", Double(bits) / 1000) }
        return "\(bits)"
    }

    private func noticeSymbol(_ kind: NoticeKind) -> String {
        switch kind {
        case .sub, .resub, .subGift, .communitySubGift, .giftPaidUpgrade, .primePaidUpgrade:
            return "★"
        case .raid, .unraid:
            return "⚑"
        case .announcement:
            return "📣"
        case .payItForward, .charityDonation, .bitsBadgeTier:
            return "✦"
        case .other:
            return "✦"
        }
    }

    private var lineHeight: CGFloat {
        ceil(font.lineHeight)
    }

    private func emoteBox(for emote: Emote) -> CGSize {
        let height = lineHeight * 1.4
        let width = max(height, height * CGFloat(emote.aspectRatio))
        return CGSize(width: ceil(width) + emoteSidePadding * 2, height: ceil(height))
    }

    private func emotePlaceholder(for emote: Emote) -> NSAttributedString {
        let attachment = NSTextAttachment()
        let box = emoteBox(for: emote)
        let descent = (box.height - font.ascender + font.descender) / 2
        attachment.bounds = CGRect(x: 0, y: font.descender - descent, width: box.width, height: box.height)
        return NSAttributedString(attachment: attachment)
    }

    private func layoutText(
        attributed: NSAttributedString,
        emoteTokens: [(emote: Emote, attributedIndex: Int)],
        textWidth: CGFloat,
        originX: CGFloat,
        originY: CGFloat
    ) -> (height: CGFloat, emotePlacements: [LaidOutMessage.EmotePlacement]) {
        let layoutManager = NSLayoutManager()
        let textStorage = NSTextStorage(attributedString: attributed)
        let textContainer = NSTextContainer(size: CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let height = ceil(layoutManager.usedRect(for: textContainer).height)

        guard !emoteTokens.isEmpty else { return (height, []) }

        var placements: [LaidOutMessage.EmotePlacement] = []
        var lastNonZeroFrame: CGRect?

        for token in emoteTokens {
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: token.attributedIndex, length: 1),
                actualCharacterRange: nil
            )
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += originX + emoteSidePadding
            rect.origin.y += originY
            rect.size.width -= emoteSidePadding * 2

            if token.emote.isZeroWidth, let base = lastNonZeroFrame {
                let centered = CGRect(
                    x: base.midX - rect.width / 2,
                    y: base.midY - rect.height / 2,
                    width: rect.width,
                    height: rect.height
                )
                placements.append(.init(emote: token.emote, frame: centered))
            } else {
                placements.append(.init(emote: token.emote, frame: rect))
                lastNonZeroFrame = rect
            }
        }

        return (height, placements)
    }

    private func resolveBadgePlacements(
        _ badges: [Badge],
        box: CGFloat,
        originY: CGFloat
    ) -> [LaidOutMessage.BadgePlacement] {
        guard !badges.isEmpty else { return [] }
        var placements: [LaidOutMessage.BadgePlacement] = []
        var x = horizontalInset
        let baselineOffset = (lineHeight - box) / 2
        for badge in badges {
            let frame = CGRect(x: x, y: originY + baselineOffset, width: box, height: box)
            placements.append(.init(badge: badge, frame: frame))
            x += box + badgeSpacing
        }
        return placements
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func timestampString(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }
}
