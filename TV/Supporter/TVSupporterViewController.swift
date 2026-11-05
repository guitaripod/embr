import UIKit
import Combine
import EmbrCore

/// Founding Supporter on the Apple TV: what it gives, the price, buy and restore, and for a supporter the accent colors
/// to choose from.
final class TVSupporterViewController: UIViewController {
    private let flame = UIImageView(image: UIImage(named: "supporter-flame"))
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let perksStack = UIStackView()
    private let buyButton = UIButton(configuration: .filled())
    private let restoreButton = UIButton(configuration: .bordered())
    private let accentStack = UIStackView()
    private let statusLabel = UILabel()
    private var accentButtons: [SupporterAccent: UIButton] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var purchasing = false

    override func viewDidLoad() {
        super.viewDidLoad()

        flame.contentMode = .scaleAspectFit

        titleLabel.font = TVFont.screenTitle
        titleLabel.textColor = Theme.primaryText
        bodyLabel.font = TVFont.body
        bodyLabel.textColor = Theme.secondaryText
        bodyLabel.numberOfLines = 0
        bodyLabel.text = String(localized: "Embr is made by one independent developer. Founding Supporters keep it free for everyone, and get a few things in return. Watching never needs it.")

        perksStack.axis = .vertical
        perksStack.spacing = 18
        for (symbol, text) in [
            ("flame.circle.fill", String(localized: "A flame badge beside your name in chat, seen by everyone watching in Embr")),
            ("paintpalette.fill", String(localized: "Seven accent colors for Embr on Apple TV, iPhone and iPad")),
            ("app.badge.fill", String(localized: "Alternate app icons on iPhone and iPad")),
            ("infinity", String(localized: "Pay once. Yours on every device signed in to your Apple Account.")),
        ] {
            perksStack.addArrangedSubview(Self.perk(symbol: symbol, text: text))
        }

        buyButton.configuration?.imagePadding = 12
        buyButton.addAction(UIAction { [weak self] _ in self?.buy() }, for: .primaryActionTriggered)
        restoreButton.configuration?.title = String(localized: "Restore Purchase")
        restoreButton.addAction(UIAction { [weak self] _ in self?.restore() }, for: .primaryActionTriggered)

        statusLabel.font = TVFont.cardSubtitle
        statusLabel.textColor = Theme.secondaryText
        statusLabel.numberOfLines = 0

        accentStack.axis = .horizontal
        accentStack.distribution = .fillEqually
        accentStack.spacing = 12
        for accent in SupporterAccent.allCases {
            let button = Self.swatch(for: accent)
            button.addAction(UIAction { _ in SupporterStore.shared.setAccent(accent) }, for: .primaryActionTriggered)
            accentButtons[accent] = button
            accentStack.addArrangedSubview(button)
        }

        let buttons = UIStackView(arrangedSubviews: [buyButton, restoreButton])
        buttons.axis = .horizontal
        buttons.spacing = 32

        let column = UIStackView(arrangedSubviews: [titleLabel, bodyLabel, perksStack, buttons, accentStack, statusLabel])
        column.axis = .vertical
        column.alignment = .leading
        column.spacing = 30
        column.setCustomSpacing(48, after: perksStack)

        let row = UIStackView(arrangedSubviews: [flame, column])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 90
        row.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(row)
        NSLayoutConstraint.activate([
            flame.widthAnchor.constraint(equalToConstant: 300),
            flame.heightAnchor.constraint(equalToConstant: 300),
            column.widthAnchor.constraint(equalToConstant: 1100),
            row.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 30),
        ])

        SupporterStore.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.render() }
            .store(in: &cancellables)
        SupporterStore.shared.loadProduct()
        render()
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        SupporterStore.shared.isSupporter
            ? [accentButtons[SupporterStore.shared.accent] ?? accentStack]
            : [buyButton]
    }

    private func render() {
        let store = SupporterStore.shared
        let supporter = store.isSupporter
        titleLabel.text = supporter ? String(localized: "Thank you for keeping Embr going") : String(localized: "Keep Embr independent")
        buyButton.isHidden = supporter
        restoreButton.isHidden = supporter
        accentStack.isHidden = !supporter
        if let price = store.product?.displayPrice {
            buyButton.configuration?.title = String(localized: "Support for \(price)")
            buyButton.isEnabled = !purchasing
        } else if store.productUnavailable {
            buyButton.configuration?.title = String(localized: "Try Again")
            buyButton.isEnabled = true
        } else {
            buyButton.configuration?.title = String(localized: "Loading Price…")
            buyButton.isEnabled = false
        }
        buyButton.configuration?.showsActivityIndicator = purchasing
        for (accent, button) in accentButtons {
            button.configuration?.image = UIImage(systemName: accent == store.accent ? "checkmark.circle.fill" : "circle.fill")
        }
        statusLabel.text = status(for: store)
        statusLabel.isHidden = statusLabel.text == nil
        setNeedsFocusUpdate()
    }

    private func status(for store: SupporterStore) -> String? {
        guard store.isSupporter else {
            return store.productUnavailable ? String(localized: "Purchases are not available right now.") : nil
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
        Task { [weak self] in
            let outcome = await SupporterStore.shared.purchase(in: self?.view.window?.windowScene)
            guard let self else { return }
            self.purchasing = false
            self.render()
            switch outcome {
            case .purchased:
                UIAccessibility.post(notification: .announcement, argument: String(localized: "Thank you for supporting Embr."))
            case .pending:
                self.alert(String(localized: "Waiting for Approval"), String(localized: "The purchase finishes once it's approved."))
            case .cancelled:
                break
            case .failed(let message):
                self.alert(String(localized: "Purchase Failed"), message)
            }
        }
    }

    private func restore() {
        Task { [weak self] in
            let restored = await SupporterStore.shared.restore()
            if !restored {
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
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold)
        icon.contentMode = .center
        icon.widthAnchor.constraint(equalToConstant: 52).isActive = true
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = UILabel()
        label.text = text
        label.font = TVFont.body
        label.textColor = Theme.primaryText
        label.numberOfLines = 0
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 22
        return row
    }

    private static func swatch(for accent: SupporterAccent) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "circle.fill")
        configuration.baseForegroundColor = accent.color
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 64, weight: .regular)
        configuration.title = accent.title
        configuration.imagePlacement = .top
        configuration.imagePadding = 10
        configuration.titleLineBreakMode = .byClipping
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = TVFont.cardSubtitle
            return updated
        }
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = accent.title
        return button
    }
}
