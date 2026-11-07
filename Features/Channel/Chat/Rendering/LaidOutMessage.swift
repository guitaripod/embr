import UIKit
import EmbrCore

struct LaidOutMessage: Sendable {
    struct EmotePlacement: Sendable {
        let emote: Emote
        let frame: CGRect
    }

    struct BadgePlacement: Sendable {
        let badge: Badge
        let frame: CGRect
    }

    struct LinkSpan: Sendable {
        let range: NSRange
        let url: URL
    }

    let height: CGFloat
    let width: CGFloat
    let attributedText: NSAttributedString
    let textOrigin: CGPoint
    let emotePlacements: [EmotePlacement]
    let badgePlacements: [BadgePlacement]
    let usernameRange: NSRange
    let links: [LinkSpan]
    let textWidth: CGFloat
    let replyHeight: CGFloat
    let isHighlighted: Bool
    let highlight: ChatHighlighter.Reason?
    let isAnnouncement: Bool
    let isCheer: Bool
    /// The kind of a subscription, raid, announcement or other channel notice the row carries, drawn as a tinted card.
    let notice: NoticeKind?

    init(
        height: CGFloat,
        width: CGFloat,
        attributedText: NSAttributedString,
        textOrigin: CGPoint,
        emotePlacements: [EmotePlacement],
        badgePlacements: [BadgePlacement],
        usernameRange: NSRange,
        links: [LinkSpan] = [],
        textWidth: CGFloat = 0,
        replyHeight: CGFloat,
        isHighlighted: Bool,
        highlight: ChatHighlighter.Reason? = nil,
        isAnnouncement: Bool = false,
        isCheer: Bool = false,
        notice: NoticeKind? = nil
    ) {
        self.height = height
        self.width = width
        self.attributedText = attributedText
        self.textOrigin = textOrigin
        self.emotePlacements = emotePlacements
        self.badgePlacements = badgePlacements
        self.usernameRange = usernameRange
        self.links = links
        self.textWidth = textWidth
        self.replyHeight = replyHeight
        self.isHighlighted = isHighlighted
        self.highlight = highlight
        self.isAnnouncement = isAnnouncement
        self.isCheer = isCheer
        self.notice = notice
    }
}

extension NSAttributedString: @unchecked @retroactive Sendable {}
