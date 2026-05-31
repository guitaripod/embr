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

    private let horizontalInset: CGFloat = 8
    private let verticalInset: CGFloat = 4
    private let badgeSpacing: CGFloat = 3
    private let emoteSidePadding: CGFloat = 1
    private let replyLineHeight: CGFloat = 16

    init(width: CGFloat, settings: Settings, catalog: EmoteCatalog, badges: BadgeCatalog) {
        let resolved: MessageLayoutSettings = settings
        let fontSize = resolved.chatMessageFontSize
        self.width = width
        self.catalog = catalog
        self.badges = badges
        self.showsTimestamps = resolved.chatShowsTimestamps
        self.emoteScale = resolved.chatPreferredEmoteScale
        self.lineSpacing = resolved.chatLineSpacing
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

        if showsTimestamps {
            let stamp = Self.timestampString(message.timestamp)
            attributed.append(NSAttributedString(string: stamp + " ", attributes: [
                .font: timestampFont,
                .foregroundColor: Theme.secondaryText,
            ]))
        }

        let usernameColor = Theme.readableUsernameColor(message.author.color)
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

        let bodyColor = message.isAction ? usernameColor : Theme.primaryText
        let tokens = MessageTokenizer.tokens(for: message, catalog: catalog)
        var emoteTokens: [(emote: Emote, attributedIndex: Int)] = []

        for token in tokens {
            switch token {
            case .text(let value):
                attributed.append(NSAttributedString(string: value, attributes: [
                    .font: font,
                    .foregroundColor: bodyColor,
                ]))
            case .mention(let ref):
                attributed.append(NSAttributedString(string: "@\(ref.displayName)", attributes: [
                    .font: usernameFont,
                    .foregroundColor: Theme.accent,
                ]))
            case .link(_, let raw):
                attributed.append(NSAttributedString(string: raw, attributes: [
                    .font: font,
                    .foregroundColor: Theme.link,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ]))
            case .cheermote(let ref):
                attributed.append(NSAttributedString(string: ref.text, attributes: [
                    .font: usernameFont,
                    .foregroundColor: Theme.accent,
                ]))
            case .emote(let emote):
                let index = attributed.length
                emoteTokens.append((emote, index))
                attributed.append(emotePlaceholder(for: emote))
            }
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        attributed.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: attributed.length))

        let textOriginX = horizontalInset + badgePrefixWidth
        let textWidth = max(1, availableWidth - badgePrefixWidth)
        let textBounds = attributed.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let textHeight = ceil(textBounds.height)
        let textOriginY = verticalInset + replyHeight

        let emotePlacements = resolveEmotePlacements(
            emoteTokens: emoteTokens,
            attributed: attributed,
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
            replyHeight: replyHeight,
            isHighlighted: isHighlighted
        )
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

    private func resolveEmotePlacements(
        emoteTokens: [(emote: Emote, attributedIndex: Int)],
        attributed: NSAttributedString,
        textWidth: CGFloat,
        originX: CGFloat,
        originY: CGFloat
    ) -> [LaidOutMessage.EmotePlacement] {
        guard !emoteTokens.isEmpty else { return [] }

        let layoutManager = NSLayoutManager()
        let textStorage = NSTextStorage(attributedString: attributed)
        let textContainer = NSTextContainer(size: CGSize(width: textWidth, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

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

        return placements
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
