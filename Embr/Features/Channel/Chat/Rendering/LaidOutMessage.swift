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

    let height: CGFloat
    let width: CGFloat
    let attributedText: NSAttributedString
    let textOrigin: CGPoint
    let emotePlacements: [EmotePlacement]
    let badgePlacements: [BadgePlacement]
    let usernameRange: NSRange
    let replyHeight: CGFloat
    let isHighlighted: Bool

    init(
        height: CGFloat,
        width: CGFloat,
        attributedText: NSAttributedString,
        textOrigin: CGPoint,
        emotePlacements: [EmotePlacement],
        badgePlacements: [BadgePlacement],
        usernameRange: NSRange,
        replyHeight: CGFloat,
        isHighlighted: Bool
    ) {
        self.height = height
        self.width = width
        self.attributedText = attributedText
        self.textOrigin = textOrigin
        self.emotePlacements = emotePlacements
        self.badgePlacements = badgePlacements
        self.usernameRange = usernameRange
        self.replyHeight = replyHeight
        self.isHighlighted = isHighlighted
    }
}

extension NSAttributedString: @unchecked @retroactive Sendable {}
