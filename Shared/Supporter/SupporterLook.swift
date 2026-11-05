import UIKit
import os
import EmbrCore

/// Whether this device shows a Founding Supporter's own look: their theme, chat font and accent. Chat layout reads it
/// on any thread, so `SupporterStore` keeps it here rather than on the main actor.
enum SupporterLook {
    private static let state = OSAllocatedUnfairLock(initialState: false)

    static var unlocked: Bool {
        state.withLock { $0 }
    }

    static func setUnlocked(_ unlocked: Bool) {
        state.withLock { $0 = unlocked }
    }
}

/// Every look a Founding Supporter picks, together: what a supporter has, or what someone tries on before buying.
struct SupporterLookChoice: Equatable, Sendable {
    var theme: SupporterTheme
    var accent: SupporterAccent
    var chatFont: SupporterChatFont
    var badgeColor: SupporterAccent
    var nameStyle: SupporterAPI.NameStyle
    /// The alternate iPhone and iPad icon; nil is Embr's own.
    var icon: String?

    /// What the purchase screen first lets someone try on: the flame and glowing name in Embr's violet, the rest as
    /// they are.
    static let tryOn = SupporterLookChoice(theme: .standard, accent: .violet, chatFont: .standard, badgeColor: .violet, nameStyle: .glow, icon: nil)
}

/// The page colors a Founding Supporter can give the whole app. Standard is Embr's own and everyone else's.
enum SupporterTheme: String, CaseIterable, Sendable {
    case standard
    case oled
    case midnight
    case ember
    case dusk

    struct Palette {
        let background: UIColor
        let surface: UIColor
        let surfaceElevated: UIColor
    }

    var title: String {
        switch self {
        case .standard: String(localized: "Standard", comment: "Theme name")
        case .oled: String(localized: "OLED Black", comment: "Theme name")
        case .midnight: String(localized: "Midnight", comment: "Theme name")
        case .ember: String(localized: "Ember", comment: "Theme name")
        case .dusk: String(localized: "Dusk", comment: "Theme name")
        }
    }

    /// The colors for one appearance; standard keeps the system's own light colors on iPhone and iPad.
    func palette(dark: Bool) -> Palette {
        switch (self, dark) {
        case (.standard, true):
            Palette(background: Self.white(0.07), surface: Self.white(0.12), surfaceElevated: Self.white(0.16))
        case (.standard, false), (.oled, false):
            Palette(background: Self.lightBackground, surface: Self.lightSurface, surfaceElevated: Self.lightBackground)
        case (.oled, true):
            Palette(background: Self.white(0), surface: Self.white(0.07), surfaceElevated: Self.white(0.11))
        case (.midnight, true):
            Palette(background: Self.rgb(9, 13, 28), surface: Self.rgb(18, 25, 46), surfaceElevated: Self.rgb(27, 36, 62))
        case (.midnight, false):
            Palette(background: Self.rgb(238, 242, 250), surface: Self.rgb(224, 231, 245), surfaceElevated: Self.rgb(247, 249, 253))
        case (.ember, true):
            Palette(background: Self.rgb(22, 12, 8), surface: Self.rgb(36, 22, 15), surfaceElevated: Self.rgb(48, 30, 21))
        case (.ember, false):
            Palette(background: Self.rgb(251, 245, 238), surface: Self.rgb(242, 231, 219), surfaceElevated: Self.rgb(255, 251, 246))
        case (.dusk, true):
            Palette(background: Self.rgb(18, 12, 28), surface: Self.rgb(30, 21, 45), surfaceElevated: Self.rgb(41, 30, 60))
        case (.dusk, false):
            Palette(background: Self.rgb(246, 242, 252), surface: Self.rgb(234, 227, 246), surfaceElevated: Self.rgb(251, 249, 255))
        }
    }

    /// The two colors a theme's preview swatch shows: the page and a card on it, in the given appearance.
    func swatch(dark: Bool) -> (page: UIColor, card: UIColor) {
        let palette = palette(dark: dark)
        return (palette.background, palette.surface)
    }

    private static func white(_ value: CGFloat) -> UIColor {
        UIColor(white: value, alpha: 1)
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }

    /// The light page color. tvOS has no system background colors, so it gets the gray the system draws behind apps.
    private static var lightBackground: UIColor {
        #if os(tvOS)
        UIColor(white: 0.92, alpha: 1.0)
        #else
        .systemBackground
        #endif
    }

    private static var lightSurface: UIColor {
        #if os(tvOS)
        UIColor(white: 0.86, alpha: 1.0)
        #else
        .secondarySystemBackground
        #endif
    }
}

/// Carries the theme down the view hierarchy, so `Theme`'s page colors resolve to it wherever they are drawn and change
/// in place when a supporter picks another one, or when the supporter screen previews one.
struct SupporterThemeTrait: UITraitDefinition {
    static let defaultValue = SupporterTheme.standard
    static let affectsColorAppearance = true
    static let name = "EmbrSupporterTheme"
}

extension UITraitCollection {
    var supporterTheme: SupporterTheme {
        self[SupporterThemeTrait.self]
    }
}

/// The typeface of chat messages a Founding Supporter can pick.
enum SupporterChatFont: String, CaseIterable, Sendable {
    case standard
    case rounded
    case serif
    case mono

    var title: String {
        switch self {
        case .standard: String(localized: "Standard", comment: "Chat font name")
        case .rounded: String(localized: "Rounded", comment: "Chat font name")
        case .serif: String(localized: "Serif", comment: "Chat font name")
        case .mono: String(localized: "Mono", comment: "Chat font name")
        }
    }

    var design: UIFontDescriptor.SystemDesign {
        switch self {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        }
    }

    func font(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard self != .standard, let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

/// The Founding Supporters' iPhone and iPad icons: the flame in each color and four designs of its own. nil is
/// Embr's own violet flame.
struct SupporterIcon: Sendable, Equatable {
    let alternateName: String?
    let previewName: String
    let title: String

    static var all: [SupporterIcon] {
        SupporterAccent.allCases.map { accent in
            SupporterIcon(
                alternateName: accent == .violet ? nil : "AppIcon-\(accent.assetSuffix)",
                previewName: "IconPreview-\(accent.assetSuffix)",
                title: accent.title
            )
        } + [
            SupporterIcon(alternateName: "AppIcon-Midnight", previewName: "IconPreview-Midnight", title: String(localized: "Midnight", comment: "App icon name")),
            SupporterIcon(alternateName: "AppIcon-Paper", previewName: "IconPreview-Paper", title: String(localized: "Paper", comment: "App icon name")),
            SupporterIcon(alternateName: "AppIcon-Neon", previewName: "IconPreview-Neon", title: String(localized: "Neon", comment: "App icon name")),
            SupporterIcon(alternateName: "AppIcon-Pixel", previewName: "IconPreview-Pixel", title: String(localized: "Pixel", comment: "App icon name")),
        ]
    }
}
