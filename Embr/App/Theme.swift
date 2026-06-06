import UIKit
import EmbrCore

enum Theme {
    static let accent = UIColor(red: 0.569, green: 0.275, blue: 1.0, alpha: 1.0)

    static let background = dynamic(light: .systemBackground, dark: UIColor(white: 0.07, alpha: 1.0))
    static let surface = dynamic(light: .secondarySystemBackground, dark: UIColor(white: 0.12, alpha: 1.0))
    static let surfaceElevated = dynamic(light: .systemBackground, dark: UIColor(white: 0.16, alpha: 1.0))

    static let primaryText = UIColor.label
    static let secondaryText = UIColor.secondaryLabel
    static let link = UIColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)

    static let liveDot = UIColor.systemRed
    static let highlightedMessage = accent.withAlphaComponent(0.16)
    static let mentionBackground = accent.withAlphaComponent(0.24)

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
}
