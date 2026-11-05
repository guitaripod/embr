import UIKit
import Combine
import EmbrCore
import MidgarCore

/// Founding Supporter on iPhone and iPad: what it gives and the purchase, and for a supporter the app icons, the
/// accent colors and the state of their chat badge.
final class SupporterViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let flame = UIImageView(image: UIImage(named: "supporter-flame"))
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let perks = UIStackView()
    private let buyButton = UIButton(configuration: .borderedProminent())
    private let restoreButton = UIButton(configuration: .plain())
    private let iconsHeader = UILabel()
    private let iconsGrid = UIStackView()
    private let accentHeader = UILabel()
    private let accentRow = UIStackView()
    private let badgeLabel = UILabel()
    private let badgeRetry = UIButton(configuration: .plain())
    private var iconButtons: [String?: UIButton] = [:]
    private var accentButtons: [SupporterAccent: UIButton] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var purchasing = false

    /// The supporters' iPhone icons: nil is Embr's own violet flame.
    private static let icons: [(name: String?, preview: String, accent: SupporterAccent)] = [
        (nil, "IconPreview-Violet", .violet),
        ("AppIcon-Ember", "IconPreview-Ember", .ember),
        ("AppIcon-Rose", "IconPreview-Rose", .rose),
        ("AppIcon-Gold", "IconPreview-Gold", .gold),
        ("AppIcon-Mint", "IconPreview-Mint", .mint),
        ("AppIcon-Ocean", "IconPreview-Ocean", .ocean),
        ("AppIcon-Frost", "IconPreview-Frost", .frost),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Founding Supporter")
        view.backgroundColor = Theme.background
        buildLayout()
        SupporterStore.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.render() }
            .store(in: &cancellables)
        SupporterStore.shared.loadProduct()
        render()
    }

    private func buildLayout() {
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 18
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 24, leading: 24, bottom: 40, trailing: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        flame.contentMode = .scaleAspectFit
        flame.heightAnchor.constraint(equalToConstant: 132).isActive = true
        flame.accessibilityIgnoresInvertColors = true

        titleLabel.font = .preferredFont(forTextStyle: .title1).bold
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.textColor = Theme.secondaryText
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0
        bodyLabel.text = String(localized: "Embr is made by one independent developer. Founding Supporters keep it free for everyone, and get a few things in return. Watching never needs it.")

        perks.axis = .vertical
        perks.spacing = 14
        for (symbol, text) in [
            ("flame.circle.fill", String(localized: "A flame badge beside your name in chat, seen by everyone watching in Embr")),
            ("paintpalette.fill", String(localized: "Seven accent colors for Embr on iPhone, iPad and Apple TV")),
            ("app.badge.fill", String(localized: "Seven app icons to match")),
            ("infinity", String(localized: "Pay once. Yours on every device signed in to your Apple Account.")),
        ] {
            perks.addArrangedSubview(Self.perk(symbol: symbol, text: text))
        }

        buyButton.configuration?.cornerStyle = .large
        buyButton.configuration?.buttonSize = .large
        buyButton.addAction(UIAction { [weak self] _ in self?.buy() }, for: .primaryActionTriggered)
        restoreButton.configuration?.title = String(localized: "Restore Purchase")
        restoreButton.addAction(UIAction { [weak self] _ in self?.restore() }, for: .primaryActionTriggered)

        iconsHeader.text = String(localized: "App Icon")
        accentHeader.text = String(localized: "Accent Color")
        for header in [iconsHeader, accentHeader] {
            header.font = .preferredFont(forTextStyle: .headline)
            header.adjustsFontForContentSizeCategory = true
        }

        iconsGrid.axis = .vertical
        iconsGrid.spacing = 14
        var row: UIStackView?
        for (index, icon) in Self.icons.enumerated() {
            if index % 4 == 0 {
                let next = UIStackView()
                next.axis = .horizontal
                next.distribution = .fillEqually
                next.spacing = 14
                iconsGrid.addArrangedSubview(next)
                row = next
            }
            let button = Self.iconButton(preview: icon.preview, title: icon.accent.title)
            button.addAction(UIAction { [weak self] _ in self?.setIcon(icon.name) }, for: .primaryActionTriggered)
            iconButtons[icon.name] = button
            row?.addArrangedSubview(button)
        }
        if let row, row.arrangedSubviews.count < 4 {
            for _ in row.arrangedSubviews.count..<4 { row.addArrangedSubview(UIView()) }
        }

        accentRow.axis = .horizontal
        accentRow.distribution = .equalSpacing
        for accent in SupporterAccent.allCases {
            let button = Self.swatch(accent)
            button.addAction(UIAction { _ in
                Haptics.selection()
                SupporterStore.shared.setAccent(accent)
            }, for: .primaryActionTriggered)
            accentButtons[accent] = button
            accentRow.addArrangedSubview(button)
        }

        badgeLabel.font = .preferredFont(forTextStyle: .footnote)
        badgeLabel.adjustsFontForContentSizeCategory = true
        badgeLabel.textColor = Theme.secondaryText
        badgeLabel.numberOfLines = 0
        badgeLabel.textAlignment = .center
        badgeRetry.configuration?.title = String(localized: "Try Again")
        badgeRetry.addAction(UIAction { _ in SupporterStore.shared.retryBadge() }, for: .primaryActionTriggered)

        [flame, titleLabel, bodyLabel, perks, buyButton, restoreButton, iconsHeader, iconsGrid, accentHeader, accentRow, badgeLabel, badgeRetry]
            .forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(28, after: perks)
        stack.setCustomSpacing(4, after: buyButton)
        stack.setCustomSpacing(10, after: iconsHeader)
        stack.setCustomSpacing(10, after: accentHeader)
        stack.setCustomSpacing(28, after: iconsGrid)
        stack.setCustomSpacing(28, after: accentRow)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 600),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor).withPriority(.defaultHigh),
        ])
    }

    private func render() {
        let store = SupporterStore.shared
        let supporter = store.isSupporter
        titleLabel.text = supporter ? String(localized: "Thank you for keeping Embr going") : String(localized: "Keep Embr independent")
        buyButton.isHidden = supporter
        restoreButton.isHidden = supporter
        [iconsHeader, iconsGrid, accentHeader, accentRow].forEach { $0.isHidden = !supporter }
        if let price = store.product?.displayPrice {
            buyButton.configuration?.title = String(localized: "Become a Supporter · \(price)")
            buyButton.isEnabled = !purchasing
        } else {
            buyButton.configuration?.title = String(localized: "Loading Price…")
            buyButton.isEnabled = false
        }
        buyButton.configuration?.showsActivityIndicator = purchasing
        buyButton.tintColor = Theme.accent
        let currentIcon = UIApplication.shared.alternateIconName
        for (name, button) in iconButtons {
            let selected = name == currentIcon
            button.configuration?.background.strokeColor = selected ? Theme.accent : .clear
            button.configuration?.background.strokeWidth = selected ? 3 : 0
            button.accessibilityTraits = selected ? [.button, .selected] : .button
        }
        for (accent, button) in accentButtons {
            let selected = accent == store.accent
            button.configuration?.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle.fill")
            button.accessibilityTraits = selected ? [.button, .selected] : .button
        }
        badgeLabel.text = badgeText(store)
        badgeLabel.isHidden = badgeLabel.text == nil
        badgeRetry.isHidden = store.badge != .failed
    }

    private func badgeText(_ store: SupporterStore) -> String? {
        guard store.isSupporter else { return nil }
        switch store.badge {
        case .needsSignIn: return String(localized: "Sign in with Twitch in Settings to show your badge in chat.")
        case .shown(let login): return String(localized: "Your badge shows beside \(login) in chat.")
        case .failed: return String(localized: "Your badge couldn't be turned on yet.")
        case .claiming: return String(localized: "Turning on your badge…")
        case .none: return nil
        }
    }

    private func setIcon(_ name: String?) {
        guard UIApplication.shared.supportsAlternateIcons, UIApplication.shared.alternateIconName != name else { return }
        Haptics.selection()
        UIApplication.shared.setAlternateIconName(name) { [weak self] error in
            if let error {
                MidgarLog.notice("supporter: icon change failed: \(error)", category: .tips)
            }
            Task { @MainActor in self?.render() }
        }
    }

    private func buy() {
        guard !purchasing else { return }
        purchasing = true
        render()
        Task { [weak self] in
            let outcome = await SupporterStore.shared.purchase(in: self?.view.window?.windowScene)
            guard let self else { return }
            self.purchasing = false
            self.render()
            switch outcome {
            case .purchased:
                Haptics.notify(.success)
            case .pending:
                self.alert(String(localized: "Waiting for Approval"), String(localized: "The purchase finishes once it's approved."))
            case .cancelled:
                break
            case .failed(let message):
                Haptics.notify(.error)
                self.alert(String(localized: "Purchase Failed"), message)
            }
        }
    }

    private func restore() {
        Task { [weak self] in
            if !(await SupporterStore.shared.restore()) {
                self?.alert(String(localized: "Nothing to Restore"), String(localized: "This Apple Account hasn't bought Founding Supporter yet."))
            }
        }
    }

    private func alert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }

    private static func perk(symbol: String, text: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = Theme.accent
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title3)
        icon.contentMode = .center
        icon.widthAnchor.constraint(equalToConstant: 34).isActive = true
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14
        return row
    }

    private static func iconButton(preview: String, title: String) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(named: preview)?.preparingThumbnail(of: CGSize(width: 64, height: 64))
        configuration.imagePlacement = .top
        configuration.imagePadding = 6
        configuration.title = title
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = .preferredFont(forTextStyle: .caption1)
            return updated
        }
        configuration.background.cornerRadius = 18
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4)
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = String(localized: "\(title) icon")
        return button
    }

    private static func swatch(_ accent: SupporterAccent) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "circle.fill")
        configuration.baseForegroundColor = accent.color
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 34)
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = accent.title
        return button
    }
}

private extension UIFont {
    var bold: UIFont {
        fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: 0) } ?? self
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
