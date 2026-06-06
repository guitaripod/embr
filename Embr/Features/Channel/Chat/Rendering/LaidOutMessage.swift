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
    let mentionsCurrentUser: Bool
    let isAnnouncement: Bool
    let isCheer: Bool

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
        mentionsCurrentUser: Bool = false,
        isAnnouncement: Bool = false,
        isCheer: Bool = false
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
        self.mentionsCurrentUser = mentionsCurrentUser
        self.isAnnouncement = isAnnouncement
        self.isCheer = isCheer
    }
}

extension NSAttributedString: @unchecked @retroactive Sendable {}
