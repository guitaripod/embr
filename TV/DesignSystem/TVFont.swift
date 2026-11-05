import UIKit

/// The font roles of the TV screens, all from the system text styles so they follow the Apple TV's text size.
@MainActor
enum TVFont {
    static var screenTitle: UIFont { .preferredFont(forTextStyle: .title2) }
    static var sectionTitle: UIFont { bold(.title3) }
    static var cardTitle: UIFont { bold(.callout) }
    static var cardSubtitle: UIFont { .preferredFont(forTextStyle: .caption1) }
    static var badge: UIFont { bold(.caption2) }
    static var body: UIFont { .preferredFont(forTextStyle: .body) }
    static var headline: UIFont { .preferredFont(forTextStyle: .headline) }

    static func bold(_ style: UIFont.TextStyle) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) else { return base }
        return UIFont(descriptor: descriptor, size: 0)
    }

    static func mono(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }
}
