import UIKit

/// The colored rounded-square glyph in front of a settings row, as in the system Settings app.
struct SettingsIcon: Hashable {
    let symbol: String
    let color: UIColor

    /// Rendered once per symbol and color and shared by every row that shows it, so scrolling and redrawing settings
    /// never draws a tile again. The image carries a light and a dark rendering, and image views pick the one that
    /// matches their appearance as it changes.
    @MainActor
    var image: UIImage {
        let key = "\(symbol)|\(color.hashValue)" as NSString
        if let cached = Self.cache.object(forKey: key) { return cached }
        let image = Self.render(symbol: symbol, color: color)
        Self.cache.setObject(image, forKey: key)
        return image
    }

    static let side: CGFloat = 29

    @MainActor private static let cache = NSCache<NSString, UIImage>()

    @MainActor
    private static func render(symbol: String, color: UIColor) -> UIImage {
        let asset = UIImageAsset()
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            asset.register(tile(symbol: symbol, color: color.resolvedColor(with: traits)), with: traits)
        }
        return asset.image(with: UITraitCollection.current)
    }

    @MainActor
    private static func tile(symbol: String, color: UIColor) -> UIImage {
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            color.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 7).fill()
            let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            guard let glyph = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
            let glyphSize = glyph.size
            glyph.draw(in: CGRect(x: (size.width - glyphSize.width) / 2, y: (size.height - glyphSize.height) / 2, width: glyphSize.width, height: glyphSize.height))
        }
    }
}

/// A choice in a row's pop-up menu.
struct SettingsChoice {
    let title: String
    let isSelected: Bool
    let select: () -> Void
}

/// One row of a settings page and what it does.
@MainActor
struct SettingsItem {
    enum Role {
        case normal
        case accent
        case destructive
    }

    enum Kind {
        /// A switch.
        case toggle(isOn: Bool, set: (Bool) -> Void)
        /// A row that opens another screen, with an optional value before the chevron.
        case link(value: String?, open: (UIViewController) -> Void)
        /// A pop-up menu showing the current choice, as the system uses for short lists.
        case menu(value: String, choices: [SettingsChoice])
        /// A tappable row that does something in place: tinted, or red when it removes something.
        case action(role: Role, run: (UIViewController, UIView?) -> Void)
        /// A purchase: the product's name with its price in the accent color.
        case price(String?, buy: (UIViewController, UIView?) -> Void)
        /// A value to read, not to change.
        case value(String?)
        case slider(value: Double, range: ClosedRange<Double>, step: Double, format: (Double) -> String, commit: (Double) -> Void)
        case stepper(value: Double, range: ClosedRange<Double>, step: Double, format: (Double) -> String, commit: (Double) -> Void)
        /// The account card at the top of Settings.
        case profile(name: String, detail: String, avatar: UIImage?, open: (UIViewController) -> Void)
        /// A row the page draws itself, once.
        case custom(make: () -> UIView)
        /// A status line with a spinner.
        case loading
    }

    let id: String
    let title: String
    var subtitle: String?
    var icon: SettingsIcon?
    let kind: Kind
    /// Extra words the search matches, besides the title.
    var keywords: [String] = []

    init(id: String, title: String, subtitle: String? = nil, icon: SettingsIcon? = nil, keywords: [String] = [], kind: Kind) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.keywords = keywords
        self.kind = kind
    }

    /// What the row shows; a row is drawn again only when this changes.
    var signature: String {
        var parts = [title, subtitle ?? "", icon?.symbol ?? ""]
        switch kind {
        case .toggle(let isOn, _): parts.append(isOn ? "on" : "off")
        case .link(let value, _): parts.append("link:" + (value ?? ""))
        case .menu(let value, let choices): parts.append("menu:" + value + choices.map(\.title).joined(separator: ","))
        case .action(let role, _): parts.append("action:\(role)")
        case .price(let price, _): parts.append("price:" + (price ?? ""))
        case .value(let value): parts.append("value:" + (value ?? ""))
        case .slider(let value, _, _, _, _): parts.append("slider:\(value)")
        case .stepper(let value, _, _, _, _): parts.append("stepper:\(value)")
        case .profile(let name, let detail, let avatar, _): parts.append("profile:\(name)|\(detail)|\(avatar.map { ObjectIdentifier($0).hashValue } ?? 0)")
        case .custom: parts.append("custom")
        case .loading: parts.append("loading")
        }
        return parts.joined(separator: "\u{1F}")
    }

    var isSelectable: Bool {
        switch kind {
        case .link, .action, .price, .profile: return true
        default: return false
        }
    }
}

struct SettingsSection {
    let id: String
    var header: String?
    var footer: String?
    let items: [SettingsItem]

    init(id: String, header: String? = nil, footer: String? = nil, items: [SettingsItem]) {
        self.id = id
        self.header = header
        self.footer = footer
        self.items = items
    }
}
