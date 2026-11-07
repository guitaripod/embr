import UIKit
import EmbrCore

enum Theme {
    /// Violet, or the accent a Founding Supporter picked.
    static var accent: UIColor { SupporterAccent.current.color }

    static let background = themed(\.background)
    static let surface = themed(\.surface)
    static let surfaceElevated = themed(\.surfaceElevated)

    /// A row in a grouped list: the system's own color, or the theme's card color when a supporter picked a theme.
    static let groupedRow = UIColor { traits in
        let themed = traits.supporterTheme.palette(dark: traits.userInterfaceStyle == .dark).surface.resolvedColor(with: traits)
        #if os(iOS)
        if traits.supporterTheme == .standard {
            return UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
        }
        #endif
        return themed
    }

    /// A grouped list row's background in the theme's colors.
    static func groupedRowBackground() -> UIBackgroundConfiguration {
        var background = UIBackgroundConfiguration.listCell()
        background.backgroundColor = groupedRow
        return background
    }

    static let primaryText = UIColor.label
    static let secondaryText = UIColor.secondaryLabel
    static let link = UIColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)

    static let liveDot = UIColor.systemRed
    static var highlightedMessage: UIColor { accent.withAlphaComponent(0.16) }
    static var mentionBackground: UIColor { accent.withAlphaComponent(0.24) }

    static let emoteOnly = UIColor.systemYellow
    static let followersOnly = UIColor.systemTeal
    static let subscribersOnly = UIColor.systemGreen
    static let slowMode = UIColor.systemOrange

    static let cheerHighlight = UIColor(red: 0.61, green: 0.24, blue: 0.91, alpha: 1.0).withAlphaComponent(0.14)

    /// Twitch bits-tier color for a cheer amount.
    static func cheerColor(forBits bits: Int) -> UIColor {
        switch bits {
        case ..<100: return UIColor(red: 0.60, green: 0.60, blue: 0.60, alpha: 1.0)
        case 100..<1000: return UIColor(red: 0.61, green: 0.24, blue: 0.91, alpha: 1.0)
        case 1000..<5000: return UIColor(red: 0.11, green: 0.70, blue: 0.65, alpha: 1.0)
        case 5000..<10000: return UIColor(red: 0.0, green: 0.60, blue: 1.0, alpha: 1.0)
        default: return UIColor(red: 0.95, green: 0.19, blue: 0.13, alpha: 1.0)
        }
    }

    /// Accent color for a chat system notice, by kind.
    static func noticeColor(_ kind: NoticeKind) -> UIColor {
        switch kind {
        case .sub, .resub, .subGift, .communitySubGift, .giftPaidUpgrade, .primePaidUpgrade:
            return subscribersOnly
        case .raid, .unraid:
            return UIColor(red: 0.0, green: 0.70, blue: 0.55, alpha: 1.0)
        case .announcement:
            return accent
        case .bitsBadgeTier:
            return UIColor(red: 0.61, green: 0.24, blue: 0.91, alpha: 1.0)
        case .moderation:
            return secondaryText
        case .payItForward, .charityDonation, .other:
            return accent
        }
    }

    static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
    }

    static func readableUsernameColor(_ color: ChatColor?) -> UIColor {
        guard let color else { return accent }
        let base = UIColor(red: CGFloat(color.red) / 255.0, green: CGFloat(color.green) / 255.0, blue: CGFloat(color.blue) / 255.0, alpha: 1.0)
        return UIColor { traits in readable(base, dark: traits.userInterfaceStyle == .dark) }
    }

    /// A Founding Supporter's flame color as their name color, kept readable on the page like a Twitch color.
    static func readableNameColor(_ color: UIColor) -> UIColor {
        UIColor { traits in readable(color, dark: traits.userInterfaceStyle == .dark) }
    }

    private static func readable(_ color: UIColor, dark: Bool) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return color }
        if dark {
            brightness = max(brightness, 0.6)
        } else {
            brightness = min(brightness, 0.7)
        }
        return UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
    }

    /// A page color that follows the supporter theme the view hierarchy carries, in light and dark.
    private static func themed(_ color: KeyPath<SupporterTheme.Palette, UIColor>) -> UIColor {
        UIColor { traits in
            traits.supporterTheme.palette(dark: traits.userInterfaceStyle == .dark)[keyPath: color].resolvedColor(with: traits)
        }
    }
}
