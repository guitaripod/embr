import UIKit

/// The ten-foot layout's numbers, in points on the 1920x1080 canvas.
enum TVMetrics {
    static let horizontalInset: CGFloat = 80
    /// Where a tab's content starts: just below the floating tab bar.
    static let tabBarClearance: CGFloat = 150
    static let shelfSpacing: CGFloat = 48
    static let itemSpacing: CGFloat = 40
    static let headerHeight: CGFloat = 56
    static let cornerRadius: CGFloat = 16
    static let captionSpacing: CGFloat = 14
    static let previewDelay: TimeInterval = 1.2

    enum Card {
        static let stream = CGSize(width: 410, height: 231)
        static let featured = CGSize(width: 740, height: 416)
        static let poster = CGSize(width: 250, height: 333)
        static let video = CGSize(width: 410, height: 231)
        static let avatar: CGFloat = 180
        static let badgeInset: CGFloat = 14
    }

    enum Duration {
        static let fade: TimeInterval = 0.25
        static let panel: TimeInterval = 0.3
    }
}
