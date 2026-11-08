import UIKit
import Combine
import EmbrCore
import MidgarCommerce
import MidgarCore

/// Studio Pro's paywall on iPhone and iPad: what Pro adds, the three plans with the yearly one chosen and set against
/// the monthly, one button to buy, Restore, and the terms with working links.
final class StudioProViewController: UIViewController {
    private let pro: StudioProStore
    private var selected = StudioProStore.yearlyID
    private var planViews: [String: StudioPlanView] = [:]
    private let buyButton = UIButton(configuration: .filled())
    private let status = UILabel()
    private var cancellables = Set<AnyCancellable>()
    private var buying = false

    init(pro: StudioProStore = .shared) {
        self.pro = pro
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = StudioPalette.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        build()
        pro.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)
        pro.loadProducts()
        refresh()
    }

    private func build() {
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let eyebrow = label(String(localized: "EMBR STUDIO PRO", comment: "Paywall eyebrow"), style: .footnote, weight: .heavy, color: StudioPalette.emberLight)
        let title = label(String(localized: "Run your stream from anywhere in the room.", comment: "Paywall title, iPhone"), style: .largeTitle, weight: .heavy, color: StudioPalette.text)
        let features = UIStackView(arrangedSubviews: [
            point("timer", String(localized: "Snooze and run ad breaks from your phone, iPad or Apple TV", comment: "Paywall feature")),
            point("speaker.wave.2.fill", String(localized: "Alert sounds for raids, gifts, cheers and ads", comment: "Paywall feature")),
            point("chart.bar.fill", String(localized: "A recap after every stream", comment: "Paywall feature")),
            point("shield.lefthalf.filled", String(localized: "Moderator mode for channels you moderate", comment: "Paywall feature")),
            point("text.bubble.fill", String(localized: "Quick messages and ad announcements in chat", comment: "Paywall feature")),
        ])
        features.axis = .vertical
        features.spacing = 14
        let plans = UIStackView()
        plans.axis = .vertical
        plans.spacing = 10
        for id in StudioProStore.productIDs {
            let plan = StudioPlanView()
            plan.addAction(UIAction { [weak self] _ in
                self?.selected = id
                Haptics.selection()
                self?.refresh()
            }, for: .primaryActionTriggered)
            planViews[id] = plan
            plans.addArrangedSubview(plan)
        }
        buyButton.configuration?.cornerStyle = .capsule
        buyButton.configuration?.baseBackgroundColor = StudioPalette.ember
        buyButton.configuration?.baseForegroundColor = .white
        buyButton.configuration?.buttonSize = .large
        buyButton.addAction(UIAction { [weak self] _ in self?.buy() }, for: .primaryActionTriggered)
        status.font = .preferredFont(forTextStyle: .footnote)
        status.adjustsFontForContentSizeCategory = true
        status.textColor = StudioPalette.emberLight
        status.numberOfLines = 0
        status.textAlignment = .center
        let restore = UIButton(configuration: .plain())
        restore.configuration?.title = String(localized: "Restore Purchases")
        restore.addAction(UIAction { [weak self] _ in self?.restore() }, for: .primaryActionTriggered)
        let terms = UIButton(configuration: .plain())
        terms.configuration?.title = String(localized: "Terms of Use", comment: "Paywall link")
        terms.addAction(UIAction { [weak self] _ in self?.openWebLink(LegalText.termsURL) }, for: .primaryActionTriggered)
        let privacy = UIButton(configuration: .plain())
        privacy.configuration?.title = String(localized: "Privacy Policy", comment: "Paywall link")
        privacy.addAction(UIAction { [weak self] _ in self?.openWebLink(LegalText.privacyURL) }, for: .primaryActionTriggered)
        let links = UIStackView(arrangedSubviews: [restore, terms, privacy])
        links.distribution = .equalSpacing
        let legal = label(String(localized: "Subscriptions renew automatically until cancelled at least 24 hours before the period ends, and are charged to your Apple Account. Manage or cancel them in your Apple Account's subscription settings. Chat, alerts, moderating your own channel and the sample stream stay free.", comment: "Paywall legal text"), style: .caption2, weight: .regular, color: StudioPalette.muted)
        let column = UIStackView(arrangedSubviews: [eyebrow, title, features, plans, buyButton, status, links, legal])
        column.axis = .vertical
        column.spacing = 20
        column.setCustomSpacing(8, after: eyebrow)
        column.setCustomSpacing(28, after: features)
        column.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(column)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            column.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            column.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            column.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
        ])
    }

    private func label(_ text: String, style: UIFont.TextStyle, weight: UIFont.Weight, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        let size = UIFont.preferredFont(forTextStyle: style).pointSize
        label.font = UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size, weight: weight))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func point(_ symbol: String, _ text: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = StudioPalette.emberLight
        icon.contentMode = .center
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body, scale: .medium)
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        let row = UIStackView(arrangedSubviews: [icon, label(text, style: .body, weight: .medium, color: StudioPalette.text)])
        row.spacing = 12
        row.alignment = .center
        return row
    }

    private func refresh() {
        let saving = pro.yearlySavingPercent
        for (id, view) in planViews {
            let product = pro.product(id)
            let price = product?.displayPrice ?? "…"
            switch id {
            case StudioProStore.yearlyID:
                view.show(title: String(localized: "Yearly", comment: "Paywall plan"), price: String(localized: "\(price) a year", comment: "Paywall plan price"), badge: saving.map { String(localized: "Save \($0)%", comment: "Paywall plan saving") }, selected: selected == id)
            case StudioProStore.monthlyID:
                view.show(title: String(localized: "Monthly", comment: "Paywall plan"), price: String(localized: "\(price) a month", comment: "Paywall plan price"), badge: nil, selected: selected == id)
            default:
                view.show(title: String(localized: "Lifetime", comment: "Paywall plan"), price: String(localized: "\(price) once", comment: "Paywall plan price"), badge: String(localized: "Pay once", comment: "Paywall plan badge"), selected: selected == id)
            }
            view.isEnabled = product != nil
        }
        if pro.isSubscriber {
            buyButton.configuration?.title = String(localized: "Studio Pro Is Yours", comment: "Paywall button")
            buyButton.isEnabled = false
            status.text = String(localized: "Thank you!", comment: "Paywall status")
            return
        }
        buyButton.configuration?.title = selected == StudioProStore.lifetimeID
            ? String(localized: "Buy Studio Pro", comment: "Paywall button")
            : String(localized: "Subscribe", comment: "Paywall button")
        buyButton.configuration?.showsActivityIndicator = buying
        buyButton.isEnabled = pro.product(selected) != nil && !buying
        if case .active(let ends) = pro.weekPhase() {
            status.text = String(localized: "Your free week has \(StudioProWeek.daysLeft(until: ends, now: Date())) days left. Nothing is charged when it ends.", comment: "Paywall status")
        } else if pro.productsUnavailable {
            status.text = String(localized: "The App Store can't be reached right now.", comment: "Paywall status")
        } else {
            status.text = nil
        }
    }

    private func buy() {
        guard !buying else { return }
        buying = true
        refresh()
        let id = selected
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.pro.purchase(id, in: self.view.window?.windowScene)
            self.buying = false
            switch outcome {
            case .purchased:
                Haptics.notify(.success)
                self.dismiss(animated: true)
            case .pending:
                self.status.text = String(localized: "Waiting for approval. Studio Pro turns on when it's approved.", comment: "Paywall status")
            case .cancelled:
                break
            case .failed(let message):
                self.status.text = message
            }
            self.refresh()
        }
    }

    private func restore() {
        Task { [weak self] in
            let restored = await self?.pro.restore() ?? false
            if restored {
                self?.dismiss(animated: true)
            } else {
                self?.status.text = String(localized: "This Apple Account has no Studio Pro purchase.", comment: "Paywall status")
            }
        }
    }
}

/// One plan on the paywall: its name, price and a badge, with a ring when chosen.
final class StudioPlanView: UIControl {
    private let titleLabel = UILabel()
    private let priceLabel = UILabel()
    private let badge = UILabel()
    private let check = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = StudioPalette.panel
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.borderWidth = 1.5
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = StudioPalette.text
        priceLabel.font = .preferredFont(forTextStyle: .subheadline)
        priceLabel.adjustsFontForContentSizeCategory = true
        priceLabel.textColor = StudioPalette.muted
        badge.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12, weight: .heavy))
        badge.textColor = UIColor(white: 0.05, alpha: 1)
        badge.backgroundColor = StudioPalette.emberLight
        badge.layer.cornerRadius = 8
        badge.clipsToBounds = true
        check.contentMode = .center
        let text = UIStackView(arrangedSubviews: [titleLabel, priceLabel])
        text.axis = .vertical
        text.spacing = 2
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [check, text, badge])
        row.spacing = 12
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            check.widthAnchor.constraint(equalToConstant: 26),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(title: String, price: String, badge text: String?, selected: Bool) {
        titleLabel.text = title
        priceLabel.text = price
        badge.text = text.map { "  \($0)  " }
        badge.isHidden = text == nil
        check.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
        check.tintColor = selected ? StudioPalette.emberLight : StudioPalette.muted
        layer.borderColor = (selected ? StudioPalette.ember : StudioPalette.line).cgColor
        accessibilityLabel = [title, price, text].compactMap { $0 }.joined(separator: ", ")
        accessibilityTraits = selected ? [.button, .selected] : .button
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.5 }
    }
}
