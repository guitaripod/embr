import UIKit
import EmbrCore

/// Every look a Founding Supporter can pick, as rows of swatches and chips: the badge and name everyone sees, then the
/// theme, accent, chat font and app icon. It shows a choice and reports each change; the supporter screen decides
/// whether the change is tried on or kept.
final class SupporterLookControls: UIStackView {
    var onChange: ((SupporterLookChoice) -> Void)?

    private var choice: SupporterLookChoice = .tryOn
    private var badgeButtons: [SupporterAccent: UIButton] = [:]
    private var accentButtons: [SupporterAccent: UIButton] = [:]
    private var themeButtons: [SupporterTheme: UIButton] = [:]
    private var fontButtons: [SupporterChatFont: UIButton] = [:]
    private var iconButtons: [String: UIButton] = [:]
    private let nameStyle = UISegmentedControl()
    private static let nameStyles: [SupporterAPI.NameStyle] = [.twitch, .color, .glow]
    private static let embrIcon = "embr"

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        spacing = 10

        addSection(String(localized: "Badge & Name"), footnote: String(localized: "Everyone watching in Embr sees your flame badge and name this way."))
        addArrangedSubview(swatchRow(into: &badgeButtons) { [weak self] color in self?.change { $0.badgeColor = color } })
        for (index, style) in Self.nameStyles.enumerated() {
            nameStyle.insertSegment(withTitle: Self.title(for: style), at: index, animated: false)
        }
        nameStyle.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let style = Self.nameStyles[self.nameStyle.selectedSegmentIndex]
            self.change { $0.nameStyle = style }
        }, for: .valueChanged)
        addArrangedSubview(nameStyle)

        addSection(String(localized: "Theme"), footnote: nil)
        addArrangedSubview(scrollingRow(SupporterTheme.allCases.map { theme in
            let button = Self.chip(title: theme.title)
            button.addAction(UIAction { [weak self] _ in self?.change { $0.theme = theme } }, for: .primaryActionTriggered)
            themeButtons[theme] = button
            return button
        }))

        addSection(String(localized: "Accent Color"), footnote: nil)
        addArrangedSubview(swatchRow(into: &accentButtons) { [weak self] accent in self?.change { $0.accent = accent } })

        addSection(String(localized: "Chat Font"), footnote: nil)
        addArrangedSubview(scrollingRow(SupporterChatFont.allCases.map { font in
            let button = Self.chip(title: font.title, chatFont: font)
            button.addAction(UIAction { [weak self] _ in self?.change { $0.chatFont = font } }, for: .primaryActionTriggered)
            fontButtons[font] = button
            return button
        }))

        if UIApplication.shared.supportsAlternateIcons {
            addSection(String(localized: "App Icon"), footnote: nil)
            addArrangedSubview(iconGrid())
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitPreferredContentSizeCategory.self]) { (self: Self, _: UITraitCollection) in
            self.show(self.choice)
            for button in self.fontButtons.values { button.setNeedsUpdateConfiguration() }
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    func show(_ choice: SupporterLookChoice) {
        self.choice = choice
        for (color, button) in badgeButtons { Self.select(swatch: button, color == choice.badgeColor) }
        for (accent, button) in accentButtons { Self.select(swatch: button, accent == choice.accent) }
        let dark = traitCollection.userInterfaceStyle == .dark
        for (theme, button) in themeButtons {
            button.configuration?.image = Self.themeSwatch(theme, dark: dark)
            Self.select(chip: button, theme == choice.theme, accent: choice.accent)
        }
        for (font, button) in fontButtons { Self.select(chip: button, font == choice.chatFont, accent: choice.accent) }
        for (name, button) in iconButtons { Self.select(icon: button, name == (choice.icon ?? Self.embrIcon), accent: choice.accent) }
        nameStyle.selectedSegmentIndex = Self.nameStyles.firstIndex(of: choice.nameStyle) ?? 0
    }

    private func change(_ edit: (inout SupporterLookChoice) -> Void) {
        var next = choice
        edit(&next)
        guard next != choice else { return }
        Haptics.selection()
        show(next)
        onChange?(next)
    }

    private func addSection(_ title: String, footnote: String?) {
        let header = UILabel()
        header.text = title
        header.font = .preferredFont(forTextStyle: .headline)
        header.adjustsFontForContentSizeCategory = true
        header.accessibilityTraits = .header
        if let last = arrangedSubviews.last { setCustomSpacing(26, after: last) }
        addArrangedSubview(header)
        guard let footnote else { return }
        let label = UILabel()
        label.text = footnote
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Theme.secondaryText
        label.numberOfLines = 0
        setCustomSpacing(4, after: header)
        addArrangedSubview(label)
    }

    private func swatchRow(into buttons: inout [SupporterAccent: UIButton], action: @escaping (SupporterAccent) -> Void) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .equalSpacing
        for color in SupporterAccent.allCases {
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: "circle.fill")
            configuration.baseForegroundColor = color.color
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 32)
            configuration.contentInsets = .zero
            let button = UIButton(configuration: configuration)
            button.accessibilityLabel = color.title
            button.addAction(UIAction { _ in action(color) }, for: .primaryActionTriggered)
            buttons[color] = button
            row.addArrangedSubview(button)
        }
        return row
    }

    private func scrollingRow(_ buttons: [UIButton]) -> UIView {
        let row = UIStackView(arrangedSubviews: buttons)
        row.axis = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.clipsToBounds = false
        scroll.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        scroll.heightAnchor.constraint(greaterThanOrEqualTo: row.heightAnchor).isActive = true
        return scroll
    }

    private func iconGrid() -> UIView {
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 12
        var row: UIStackView?
        for (index, icon) in SupporterIcon.all.enumerated() {
            if index % 4 == 0 {
                let next = UIStackView()
                next.axis = .horizontal
                next.distribution = .fillEqually
                next.spacing = 12
                grid.addArrangedSubview(next)
                row = next
            }
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(named: icon.previewName)?.preparingThumbnail(of: CGSize(width: 60, height: 60))
            configuration.imagePlacement = .top
            configuration.imagePadding = 6
            configuration.title = icon.title
            configuration.titleLineBreakMode = .byTruncatingTail
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var updated = attributes
                updated.font = .preferredFont(forTextStyle: .caption1)
                return updated
            }
            configuration.background.cornerRadius = 18
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 2, bottom: 8, trailing: 2)
            let button = UIButton(configuration: configuration)
            button.accessibilityLabel = String(localized: "\(icon.title) icon")
            button.addAction(UIAction { [weak self] _ in self?.change { $0.icon = icon.alternateName } }, for: .primaryActionTriggered)
            iconButtons[icon.alternateName ?? Self.embrIcon] = button
            row?.addArrangedSubview(button)
        }
        if let row, row.arrangedSubviews.count < 4 {
            for _ in row.arrangedSubviews.count..<4 { row.addArrangedSubview(UIView()) }
        }
        return grid
    }

    private static func title(for style: SupporterAPI.NameStyle) -> String {
        switch style {
        case .twitch: String(localized: "Twitch Color")
        case .color: String(localized: "Flame Color")
        case .glow: String(localized: "Glow")
        }
    }

    /// A pill button; a chat font's chip shows its name in that font, at the current text size.
    private static func chip(title: String, image: UIImage? = nil, chatFont: SupporterChatFont? = nil) -> UIButton {
        var configuration = UIButton.Configuration.gray()
        configuration.title = title
        configuration.image = image
        configuration.imagePadding = 8
        configuration.cornerStyle = .capsule
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            let size = UIFont.preferredFont(forTextStyle: .subheadline).pointSize
            updated.font = chatFont?.font(ofSize: size, weight: .semibold) ?? .preferredFont(forTextStyle: .subheadline)
            return updated
        }
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = title
        return button
    }

    /// A theme's page and card colors as one circle, half each, in the given appearance.
    private static func themeSwatch(_ theme: SupporterTheme, dark: Bool) -> UIImage {
        let size = CGSize(width: 22, height: 22)
        let swatch = theme.swatch(dark: dark)
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        return UIGraphicsImageRenderer(size: size).image { context in
            let circle = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5))
            circle.addClip()
            swatch.page.resolvedColor(with: traits).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            swatch.card.resolvedColor(with: traits).setFill()
            context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
            UIColor.separator.resolvedColor(with: traits).setStroke()
            circle.lineWidth = 1
            circle.stroke()
        }.withRenderingMode(.alwaysOriginal)
    }

    private static func select(swatch button: UIButton, _ selected: Bool) {
        button.configuration?.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle.fill")
        button.accessibilityTraits = selected ? [.button, .selected] : .button
    }

    private static func select(chip button: UIButton, _ selected: Bool, accent: SupporterAccent) {
        button.configuration?.baseBackgroundColor = selected ? accent.color : nil
        button.configuration?.baseForegroundColor = selected ? (accent.prefersDarkText ? .black : .white) : nil
        button.accessibilityTraits = selected ? [.button, .selected] : .button
    }

    private static func select(icon button: UIButton, _ selected: Bool, accent: SupporterAccent) {
        button.configuration?.background.strokeColor = selected ? accent.color : .clear
        button.configuration?.background.strokeWidth = selected ? 3 : 0
        button.accessibilityTraits = selected ? [.button, .selected] : .button
    }
}
