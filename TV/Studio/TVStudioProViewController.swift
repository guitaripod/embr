import UIKit
import Combine
import EmbrCore
import MidgarCommerce
import MidgarCore

/// Studio Pro's paywall on the TV: what Pro adds, the three plans with the yearly one first, Restore, and the terms.
final class TVStudioProViewController: UIViewController {
    private let pro: StudioProStore
    private let plans = UIStackView()
    private let status = UILabel()
    private var buttons: [String: UIButton] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var buying = false

    init(pro: StudioProStore = .shared) {
        self.pro = pro
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = StudioPalette.background
        build()
        pro.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)
        pro.loadProducts()
        refresh()
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        buttons[StudioProStore.yearlyID].map { [$0] } ?? []
    }

    private func build() {
        let eyebrow = UILabel()
        eyebrow.text = String(localized: "EMBR STUDIO PRO", comment: "Paywall eyebrow")
        eyebrow.font = .systemFont(ofSize: 26, weight: .heavy)
        eyebrow.textColor = StudioPalette.emberLight
        let title = UILabel()
        title.text = String(localized: "Run your stream from the couch.", comment: "Paywall title")
        title.font = .systemFont(ofSize: 64, weight: .heavy)
        title.textColor = StudioPalette.text
        title.numberOfLines = 2
        let points = UIStackView(arrangedSubviews: Self.features.map { Self.point($0.0, $0.1) })
        points.axis = .vertical
        points.spacing = 22
        let foot = UILabel()
        foot.text = String(localized: "Chat, alerts, moderating your own channel and the sample stream stay free. Studio Pro works on iPhone, iPad and Apple TV with the same Apple Account.", comment: "Paywall footnote")
        foot.font = .systemFont(ofSize: 24)
        foot.textColor = StudioPalette.muted
        foot.numberOfLines = 0
        let left = UIStackView(arrangedSubviews: [eyebrow, title, points, foot])
        left.axis = .vertical
        left.spacing = 30

        plans.axis = .vertical
        plans.spacing = 24
        for id in StudioProStore.productIDs {
            let button = UIButton(configuration: .bordered())
            button.configuration?.titleAlignment = .leading
            button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 22, leading: 30, bottom: 22, trailing: 30)
            button.addAction(UIAction { [weak self] _ in self?.buy(id) }, for: .primaryActionTriggered)
            buttons[id] = button
            plans.addArrangedSubview(button)
        }
        let restore = UIButton(configuration: .plain())
        restore.configuration?.title = String(localized: "Restore Purchases")
        restore.addAction(UIAction { [weak self] _ in self?.restore() }, for: .primaryActionTriggered)
        let close = UIButton(configuration: .plain())
        close.configuration?.title = String(localized: "Not Now", comment: "Paywall close")
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .primaryActionTriggered)
        let small = UIStackView(arrangedSubviews: [restore, close])
        small.spacing = 30
        status.font = .systemFont(ofSize: 24, weight: .semibold)
        status.textColor = StudioPalette.emberLight
        status.numberOfLines = 0
        let legal = UILabel()
        legal.text = String(localized: "Subscriptions renew automatically until cancelled at least 24 hours before the period ends, and are charged to your Apple Account. Manage or cancel them in your Apple Account's subscription settings. Terms of Use: midgarcorp.cc/legal/embr/terms · Privacy: midgarcorp.cc/legal/embr/privacy", comment: "Paywall legal text")
        legal.font = .systemFont(ofSize: 20)
        legal.textColor = StudioPalette.muted
        legal.numberOfLines = 0
        let right = UIStackView(arrangedSubviews: [plans, status, small, legal])
        right.axis = .vertical
        right.spacing = 26

        let row = UIStackView(arrangedSubviews: [left, right])
        row.spacing = 100
        row.alignment = .center
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 130),
            row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -130),
            row.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private static var features: [(String, String)] {
        [
            ("timer", String(localized: "Snooze and run ad breaks from the remote, iPhone or iPad", comment: "Paywall feature")),
            ("speaker.wave.2.fill", String(localized: "Alert sounds through the TV", comment: "Paywall feature")),
            ("chart.bar.fill", String(localized: "A recap after every stream", comment: "Paywall feature")),
            ("shield.lefthalf.filled", String(localized: "Moderator mode for channels you moderate", comment: "Paywall feature")),
            ("text.bubble.fill", String(localized: "Quick messages and ad announcements in chat", comment: "Paywall feature")),
        ]
    }

    private static func point(_ symbol: String, _ text: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = StudioPalette.emberLight
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .bold)
        icon.contentMode = .center
        icon.widthAnchor.constraint(equalToConstant: 50).isActive = true
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 30, weight: .medium)
        label.textColor = StudioPalette.text
        label.numberOfLines = 2
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.spacing = 20
        row.alignment = .center
        return row
    }

    private func refresh() {
        if pro.isSubscriber {
            status.text = String(localized: "Studio Pro is yours. Thank you!", comment: "Paywall status")
        } else if case .active(let ends) = pro.weekPhase() {
            status.text = String(localized: "Your free week has \(StudioProWeek.daysLeft(until: ends, now: Date())) days left. Nothing is charged when it ends.", comment: "Paywall status")
        } else if pro.productsUnavailable {
            status.text = String(localized: "The App Store can't be reached right now.", comment: "Paywall status")
        } else {
            status.text = nil
        }
        let saving = pro.yearlySavingPercent
        for (id, button) in buttons {
            let product = pro.product(id)
            let price = product?.displayPrice ?? "…"
            switch id {
            case StudioProStore.yearlyID:
                button.configuration?.title = String(localized: "Yearly · \(price) a year", comment: "Paywall plan")
                button.configuration?.subtitle = saving.map { String(localized: "Save \($0)% against monthly", comment: "Paywall plan saving") }
            case StudioProStore.monthlyID:
                button.configuration?.title = String(localized: "Monthly · \(price) a month", comment: "Paywall plan")
                button.configuration?.subtitle = nil
            default:
                button.configuration?.title = String(localized: "Lifetime · \(price) once", comment: "Paywall plan")
                button.configuration?.subtitle = String(localized: "Pay once, keep it for good", comment: "Paywall plan")
            }
            button.isEnabled = product != nil && !pro.isSubscriber && !buying
        }
    }

    private func buy(_ id: String) {
        guard !buying else { return }
        buying = true
        refresh()
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.pro.purchase(id, in: self.view.window?.windowScene)
            self.buying = false
            switch outcome {
            case .purchased:
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
