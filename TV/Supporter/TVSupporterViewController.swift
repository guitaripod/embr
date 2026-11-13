import UIKit
import Combine
import EmbrCore

/// Founding Supporter on the Apple TV. Before the purchase every look can be tried on with the remote, on this screen
/// and in a chat preview drawn by the real chat, and the purchase keeps what was tried on. For a supporter the same
/// rows change the app at once.
final class TVSupporterViewController: UIViewController {
    private let flame = UIImageView()
    private let preview = SupporterChatPreview()
    private let scrollView = UIScrollView()
    private let column = UIStackView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let buyButton = UIButton(configuration: .filled())
    private let restoreButton = UIButton(configuration: .bordered())
    private let statusLabel = UILabel()
    private var badgeButtons: [SupporterAccent: UIButton] = [:]
    private var accentButtons: [SupporterAccent: UIButton] = [:]
    private var styleButtons: [SupporterAPI.NameStyle: UIButton] = [:]
    private var themeButtons: [SupporterTheme: UIButton] = [:]
    private var fontButtons: [SupporterChatFont: UIButton] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var purchasing = false
    private var draft = SupporterLookChoice.tryOn

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        flame.contentMode = .scaleAspectFit

        titleLabel.font = TVFont.screenTitle
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 0
        bodyLabel.font = TVFont.body
        bodyLabel.textColor = Theme.secondaryText
        bodyLabel.numberOfLines = 0

        buyButton.configuration?.imagePadding = 12
        buyButton.addAction(UIAction { [weak self] _ in self?.buy() }, for: .primaryActionTriggered)
        restoreButton.configuration?.title = String(localized: "Restore Purchase")
        restoreButton.addAction(UIAction { [weak self] _ in self?.restore() }, for: .primaryActionTriggered)
        let buttons = UIStackView(arrangedSubviews: [buyButton, restoreButton])
        buttons.axis = .horizontal
        buttons.spacing = 32

        statusLabel.font = TVFont.cardSubtitle
        statusLabel.textColor = Theme.secondaryText
        statusLabel.numberOfLines = 0

        column.axis = .vertical
        column.alignment = .leading
        column.spacing = 18
        [titleLabel, bodyLabel, buttons, statusLabel].forEach(column.addArrangedSubview)
        column.setCustomSpacing(36, after: bodyLabel)
        column.setCustomSpacing(12, after: buttons)

        addSection(String(localized: "Badge & Name"), footnote: String(localized: "Everyone watching in Embr sees your flame badge and name this way."))
        column.addArrangedSubview(row(SupporterAccent.allCases.map { color in
            let button = Self.swatch(color)
            button.addAction(UIAction { [weak self] _ in self?.change { $0.badgeColor = color } }, for: .primaryActionTriggered)
            badgeButtons[color] = button
            return button
        }))
        column.addArrangedSubview(row([SupporterAPI.NameStyle.twitch, .color, .glow].map { style in
            let button = Self.chip(Self.title(for: style))
            button.addAction(UIAction { [weak self] _ in self?.change { $0.nameStyle = style } }, for: .primaryActionTriggered)
            styleButtons[style] = button
            return button
        }))
        addSection(String(localized: "Theme"), footnote: nil)
        column.addArrangedSubview(row(SupporterTheme.allCases.map { theme in
            let button = Self.chip(theme.title)
            button.addAction(UIAction { [weak self] _ in self?.change { $0.theme = theme } }, for: .primaryActionTriggered)
            themeButtons[theme] = button
            return button
        }))
        addSection(String(localized: "Accent Color"), footnote: nil)
        column.addArrangedSubview(row(SupporterAccent.allCases.map { accent in
            let button = Self.swatch(accent)
            button.addAction(UIAction { [weak self] _ in self?.change { $0.accent = accent } }, for: .primaryActionTriggered)
            accentButtons[accent] = button
            return button
        }))
        addSection(String(localized: "Chat Font"), footnote: nil)
        column.addArrangedSubview(row(SupporterChatFont.allCases.map { font in
            let button = Self.chip(font.title, font: font.font(ofSize: 27, weight: .semibold))
            button.addAction(UIAction { [weak self] _ in self?.change { $0.chatFont = font } }, for: .primaryActionTriggered)
            fontButtons[font] = button
            return button
        }))

        column.isLayoutMarginsRelativeArrangement = true
        column.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 20, leading: 20, bottom: 80, trailing: 20)
        column.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(column)
        scrollView.clipsToBounds = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        flame.translatesAutoresizingMaskIntoConstraints = false
        preview.translatesAutoresizingMaskIntoConstraints = false
        [flame, preview, scrollView].forEach(view.addSubview)

        NSLayoutConstraint.activate([
            flame.topAnchor.constraint(equalTo: view.topAnchor, constant: TVMetrics.tabBarClearance + 20),
            flame.centerXAnchor.constraint(equalTo: preview.centerXAnchor),
            flame.widthAnchor.constraint(equalToConstant: 220),
            flame.heightAnchor.constraint(equalToConstant: 220),
            preview.topAnchor.constraint(equalTo: flame.bottomAnchor, constant: 36),
            preview.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: TVMetrics.horizontalInset + 20),
            preview.widthAnchor.constraint(equalToConstant: 640),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: TVMetrics.tabBarClearance),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: preview.trailingAnchor, constant: 80),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -TVMetrics.horizontalInset),
            column.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            column.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            column.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        setContentScrollView(scrollView)
        SupporterStore.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.render() }
            .store(in: &cancellables)
        SupporterStore.shared.loadProduct()
        render()
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        SupporterStore.shared.isSupporter
            ? [badgeButtons[SupporterStore.shared.choice.badgeColor] ?? column]
            : [buyButton]
    }

    private var shown: SupporterLookChoice {
        SupporterStore.shared.isSupporter ? SupporterStore.shared.choice : draft
    }

    private func change(_ edit: (inout SupporterLookChoice) -> Void) {
        let store = SupporterStore.shared
        var next = shown
        edit(&next)
        guard next != shown else { return }
        guard store.isSupporter else {
            draft = next
            render()
            return
        }
        let current = store.choice
        if next.theme != current.theme { store.setTheme(next.theme) }
        if next.accent != current.accent { store.setAccent(next.accent) }
        if next.chatFont != current.chatFont { store.setChatFont(next.chatFont) }
        if next.badgeColor != current.badgeColor || next.nameStyle != current.nameStyle {
            store.setBadgeStyle(color: next.badgeColor, nameStyle: next.nameStyle)
        }
        render()
    }

    private func render() {
        let store = SupporterStore.shared
        let supporter = store.isSupporter
        let look = shown
        if supporter {
            traitOverrides.remove(SupporterThemeTrait.self)
            view.tintColor = nil
        } else {
            traitOverrides[SupporterThemeTrait.self] = look.theme
            view.tintColor = look.accent.color
        }
        flame.image = look.badgeColor.flameImage
        preview.show(look, number: supporter ? store.number : nil)

        if supporter {
            titleLabel.text = SupporterCopy.name(number: store.number)
            bodyLabel.text = SupporterCopy.ownerBody
        } else {
            titleLabel.text = SupporterCopy.invitation
            bodyLabel.text = SupporterCopy.invitationBody
        }
        buyButton.isHidden = supporter
        restoreButton.isHidden = supporter
        let wasEnabled = buyButton.isEnabled
        if let price = store.product?.displayPrice {
            buyButton.configuration?.title = String(localized: "Unlock for \(price)")
            buyButton.isEnabled = !purchasing
        } else if store.productUnavailable {
            buyButton.configuration?.title = String(localized: "Try Again")
            buyButton.isEnabled = true
        } else {
            buyButton.configuration?.title = String(localized: "Loading Price…")
            buyButton.isEnabled = false
        }
        buyButton.configuration?.showsActivityIndicator = purchasing
        if !supporter, !wasEnabled, buyButton.isEnabled, restoreButton.isFocused {
            setNeedsFocusUpdate()
        }

        for (color, button) in badgeButtons { Self.select(swatch: button, color == look.badgeColor) }
        for (accent, button) in accentButtons { Self.select(swatch: button, accent == look.accent) }
        for (style, button) in styleButtons { Self.select(chip: button, style == look.nameStyle) }
        for (theme, button) in themeButtons { Self.select(chip: button, theme == look.theme) }
        for (font, button) in fontButtons { Self.select(chip: button, font == look.chatFont) }

        statusLabel.text = status(for: store)
        statusLabel.isHidden = statusLabel.text == nil
    }

    private func status(for store: SupporterStore) -> String? {
        guard store.isSupporter else {
            if store.productUnavailable { return String(localized: "Purchases are not available right now.") }
            return SupporterCopy.purchaseNote(count: store.supporterCount)
        }
        switch store.badge {
        case .needsSignIn: return String(localized: "Sign in with Twitch in Settings to show your badge in chat.")
        case .shown(let login): return String(localized: "Your badge shows beside \(login) in chat.")
        case .failed: return String(localized: "Your badge couldn't be turned on yet. Embr tries again next time it opens.")
        case .claiming: return String(localized: "Turning on your badge…")
        case .none: return nil
        }
    }

    private func buy() {
        guard !purchasing else { return }
        guard SupporterStore.shared.product != nil else {
            SupporterStore.shared.loadProduct()
            return
        }
        purchasing = true
        render()
        let tried = draft
        Task { [weak self] in
            let outcome = await SupporterStore.shared.purchase(in: self?.view.window?.windowScene, tryingOn: tried)
            guard let self else { return }
            self.purchasing = false
            switch outcome {
            case .purchased:
                self.render()
                self.setNeedsFocusUpdate()
                SupporterCelebration.play(from: self.flame, color: SupporterStore.shared.choice.badgeColor.color)
                UIAccessibility.post(notification: .announcement, argument: SupporterCopy.bought(number: SupporterStore.shared.number))
            case .pending:
                self.render()
                self.alert(String(localized: "Waiting for Approval"), String(localized: "The purchase finishes once it's approved."))
            case .cancelled:
                self.render()
            case .failed(let message):
                self.render()
                self.alert(String(localized: "Purchase Failed"), message)
            }
        }
    }

    private func restore() {
        Task { [weak self] in
            let restored = await SupporterStore.shared.restore()
            if !restored {
                self?.alert(String(localized: "Nothing to Restore"), SupporterCopy.nothingToRestore)
            }
        }
    }

    private func alert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }

    private func addSection(_ title: String, footnote: String?) {
        let header = UILabel()
        header.text = title
        header.font = TVFont.sectionTitle
        header.textColor = Theme.primaryText
        if let last = column.arrangedSubviews.last { column.setCustomSpacing(44, after: last) }
        column.addArrangedSubview(header)
        guard let footnote else { return }
        let label = UILabel()
        label.text = footnote
        label.font = TVFont.cardSubtitle
        label.textColor = Theme.secondaryText
        label.numberOfLines = 0
        column.setCustomSpacing(6, after: header)
        column.addArrangedSubview(label)
    }

    private func row(_ buttons: [UIButton]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: buttons)
        row.axis = .horizontal
        row.spacing = 18
        buttons.forEach { $0.setContentCompressionResistancePriority(.required, for: .horizontal) }
        return row
    }

    private static func title(for style: SupporterAPI.NameStyle) -> String {
        switch style {
        case .twitch: String(localized: "Twitch Color")
        case .color: String(localized: "Flame Color")
        case .glow: String(localized: "Glow")
        }
    }

    private static func chip(_ title: String, font: UIFont? = nil) -> UIButton {
        var configuration = UIButton.Configuration.bordered()
        configuration.title = title
        configuration.imagePadding = 10
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)
        configuration.titleLineBreakMode = .byClipping
        let chipFont = font ?? .systemFont(ofSize: 27, weight: .medium)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = chipFont
            return updated
        }
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = title
        return button
    }

    private static func swatch(_ color: SupporterAccent) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "circle.fill")
        configuration.baseForegroundColor = color.color
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 54, weight: .regular)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = color.title
        return button
    }

    private static func select(swatch button: UIButton, _ selected: Bool) {
        button.configuration?.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle.fill")
        button.accessibilityTraits = selected ? [.button, .selected] : .button
    }

    private static func select(chip button: UIButton, _ selected: Bool) {
        button.configuration?.image = selected ? UIImage(systemName: "checkmark") : nil
        button.accessibilityTraits = selected ? [.button, .selected] : .button
    }
}
