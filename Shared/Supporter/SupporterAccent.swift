import UIKit
import os
import EmbrCore

/// The colors a Founding Supporter can give Embr: as the accent, the app's tint, mentions in chat and the live
/// highlights, seen only by them; as the flame color, their chat badge and name, seen by everyone in Embr. Everyone
/// else, and a supporter who keeps the default, sees violet.
enum SupporterAccent: String, CaseIterable, Sendable {
    case violet
    case ember
    case rose
    case gold
    case mint
    case ocean
    case frost

    var color: UIColor {
        switch self {
        case .violet: UIColor(red: 0.569, green: 0.275, blue: 1.0, alpha: 1.0)
        case .ember: UIColor(red: 1.0, green: 0.42, blue: 0.24, alpha: 1.0)
        case .rose: UIColor(red: 1.0, green: 0.31, blue: 0.60, alpha: 1.0)
        case .gold: UIColor(red: 0.96, green: 0.72, blue: 0.24, alpha: 1.0)
        case .mint: UIColor(red: 0.18, green: 0.80, blue: 0.60, alpha: 1.0)
        case .ocean: UIColor(red: 0.24, green: 0.56, blue: 1.0, alpha: 1.0)
        case .frost: UIColor(red: 0.45, green: 0.80, blue: 0.95, alpha: 1.0)
        }
    }

    var title: String {
        switch self {
        case .violet: String(localized: "Violet", comment: "Accent color name")
        case .ember: String(localized: "Ember", comment: "Accent color name")
        case .rose: String(localized: "Rose", comment: "Accent color name")
        case .gold: String(localized: "Gold", comment: "Accent color name")
        case .mint: String(localized: "Mint", comment: "Accent color name")
        case .ocean: String(localized: "Ocean", comment: "Accent color name")
        case .frost: String(localized: "Frost", comment: "Accent color name")
        }
    }

    /// The capitalized name the color's assets carry: `AppIcon-Ember`, `IconPreview-Ember`.
    var assetSuffix: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// Whether text on a fill of this color reads better in black than in white: the light colors.
    var prefersDarkText: Bool {
        switch self {
        case .gold, .mint, .frost: true
        case .violet, .ember, .rose, .ocean: false
        }
    }

    /// The large flame in this color, for the supporter screens.
    var flameImage: UIImage? {
        UIImage(named: "supporter-flame-\(rawValue)")
    }

    /// The chat badge in this color, bundled so it never waits on the network.
    var badge: Badge {
        Self.badges[self] ?? Self.makeBadge(self)
    }

    private static let badges: [SupporterAccent: Badge] = Dictionary(uniqueKeysWithValues: allCases.map { ($0, makeBadge($0)) })

    private static func makeBadge(_ accent: SupporterAccent) -> Badge {
        var urls: [EmoteScale: URL] = [:]
        for (scale, pixels) in [(EmoteScale.x1, 18), (.x2, 36), (.x4, 72)] {
            if let url = Bundle.main.url(forResource: "supporter-badge-\(accent.rawValue)-\(pixels)", withExtension: "png") {
                urls[scale] = url
            }
        }
        return Badge(
            id: "1",
            setID: "embr-supporter",
            version: accent.rawValue,
            title: String(localized: "Embr Founding Member"),
            provider: .embr,
            images: EmoteImageSet(urlsByScale: urls)
        )
    }

    private static let state = OSAllocatedUnfairLock(initialState: SupporterAccent.violet)

    /// The accent in use right now. `Theme` reads it from chat layout on any thread.
    static var current: SupporterAccent {
        state.withLock { $0 }
    }

    static func activate(_ accent: SupporterAccent) {
        state.withLock { $0 = accent }
    }
}
