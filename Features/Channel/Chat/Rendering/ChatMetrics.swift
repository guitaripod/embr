import UIKit

/// The one grid chat lines up on: message rows, the composer and every bar over the chat share its side margin, so a
/// message's first character, the composer's text and the pills all start on the same vertical line.
enum ChatMetrics {
    #if os(tvOS)
    static let edge: CGFloat = 8
    #else
    static let edge: CGFloat = 12
    #endif

    static let rowVertical: CGFloat = 4

    /// How far a highlighted or notice row's tinted card sits in from the sides; the text keeps to `edge`.
    static let cardInset: CGFloat = 4
    static let cardRadius: CGFloat = 8
    static let cardBar: CGFloat = 3

    /// The composer field's single-line height, which the send button matches so their centers line up.
    static let field: CGFloat = 40
    static let fieldMaxHeight: CGFloat = 136
    static let fieldTextInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 44)
    static let sendDiameter: CGFloat = 34
    static let rowSpacing: CGFloat = 8
    static let composerVertical: CGFloat = 8

    /// Twitch drops chat messages longer than this.
    static let messageLimit = 500
    /// The remaining-characters count shows once a draft gets this close to the limit.
    static let counterThreshold = 60
}
