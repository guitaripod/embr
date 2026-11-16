import Combine
import UIKit

/// What Hyper Low Latency does and costs, opened from its Experimental badge in Settings, its Hyper badge on the
/// player and its card on Founding Member, with the switch that turns it on and off for a Founding Member and the way to
/// Founding Member for anyone else.
@MainActor
final class HyperLatencyInfoViewController: UIViewController {

    private struct Topic {
        let symbol: String
        let tint: UIColor
        let title: String
        let body: String
    }

    private static let topics: [Topic] = [
        Topic(
            symbol: "bolt.fill",
            tint: ExperimentalBadge.colors[0],
            title: String(localized: "Closer to the moment"),
            body: String(localized: "Embr starts playing each new piece of the stream while Twitch is still sending it, instead of waiting for the piece to finish.")
        ),
        Topic(
            symbol: "dot.radiowaves.left.and.right",
            tint: ExperimentalBadge.colors[1],
            title: String(localized: "On low-latency channels"),
            body: String(localized: "It works when the streamer has Twitch's Low Latency setting on, which is the default. Other channels play as they always do.")
        ),
        Topic(
            symbol: "slider.horizontal.3",
            tint: ExperimentalBadge.colors[2],
            title: String(localized: "One quality at a time"),
            body: String(localized: "Auto plays up to 720p and stays there instead of adapting to your connection. Choose a higher quality in the player when your connection keeps up.")
        ),
        Topic(
            symbol: "wifi.exclamationmark",
            tint: .systemOrange,
            title: String(localized: "Less room for a slow connection"),
            body: String(localized: "With less video loaded ahead, a weak or busy connection pauses sooner. Turn Hyper Low Latency off if a stream keeps buffering.")
        ),
        Topic(
            symbol: "flame.fill",
            tint: .systemOrange,
            title: String(localized: "Comes with Founding Member"),
            body: String(localized: "Each Hyper viewer costs Embr's server about twice as much as a standard one, so Hyper Low Latency comes with Founding Member, a one-time purchase.")
        ),
        Topic(
            symbol: "flask.fill",
            tint: .systemTeal,
            title: String(localized: "An experiment"),
            body: String(localized: "Hyper Low Latency may change or go away in an update.")
        ),
    ]

    private let store: SettingsStore
    private let supporter: SupporterStore
    private let toggle = UISwitch()
    private let accessSlot = UIStackView()
    private var showsSwitch: Bool?
    private var bars: [(empty: NSLayoutConstraint, full: NSLayoutConstraint)] = []
    private var barsShown = false
    private var cancellables = Set<AnyCancellable>()

    init(store: SettingsStore = .shared, supporter: SupporterStore = .shared) {
        self.store = store
        self.supporter = supporter
        super.init(nibName: nil, bundle: nil)
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        build()
        store.changes.map { _ in () }
            .merge(with: supporter.changes)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.renderAccess() }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !barsShown else { return }
        barsShown = true
        growBars()
    }

    private func build() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)

        accessSlot.axis = .vertical
        renderAccess()
        let stack = UIStackView(arrangedSubviews: [makeHeader(), makeComparison(), accessSlot])
        stack.axis = .vertical
        stack.spacing = 14
        stack.setCustomSpacing(24, after: stack.arrangedSubviews[0])
        stack.translatesAutoresizingMaskIntoConstraints = false
        for topic in Self.topics { stack.addArrangedSubview(makeCard(topic)) }
        scroll.addSubview(stack)

        let done = makeDoneButton()
        view.addSubview(done)
        let fade = ScrollFadeView()
        view.addSubview(fade)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: done.topAnchor, constant: -8),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 30),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),

            done.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            done.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            done.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            done.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),

            fade.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fade.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fade.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            fade.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    private func makeHeader() -> UIView {
        let orb = HyperOrbView()
        let badge = ExperimentalBadge(style: .experimental)
        badge.isUserInteractionEnabled = false

        let title = UILabel()
        title.text = String(localized: "Hyper Low Latency")
        title.font = UIFontMetrics(forTextStyle: .title1).scaledFont(for: Self.roundedBold(size: 28))
        title.adjustsFontForContentSizeCategory = true
        title.textColor = Theme.primaryText
        title.textAlignment = .center
        title.numberOfLines = 0

        let subtitle = UILabel()
        subtitle.text = String(localized: "Watch live streams closer to the moment they happen.")
        subtitle.font = .preferredFont(forTextStyle: .body)
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.textColor = Theme.secondaryText
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [orb, badge, title, subtitle])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.setCustomSpacing(16, after: orb)
        stack.setCustomSpacing(12, after: badge)
        stack.setCustomSpacing(6, after: title)
        return stack
    }

    /// Two bars measuring how far behind the streamer each mode plays, the Hyper one in the badge's colors.
    private func makeComparison() -> UIView {
        let heading = UILabel()
        heading.text = String(localized: "Behind the streamer")
        heading.font = .preferredFont(forTextStyle: .footnote).withWeight(.semibold)
        heading.adjustsFontForContentSizeCategory = true
        heading.textColor = Theme.secondaryText

        let scale: CGFloat = 12
        let standard = makeBar(
            title: String(localized: "Standard", comment: "Latency mode name"),
            value: String(localized: "about 10 s", comment: "Seconds behind the streamer in the standard mode"),
            fraction: 10 / scale,
            fill: .systemGray3
        )
        let hyper = makeBar(
            title: String(localized: "Hyper", comment: "Latency mode name"),
            value: String(localized: "about 6–7 s", comment: "Seconds behind the streamer in Hyper Low Latency"),
            fraction: 6.5 / scale,
            gradient: ExperimentalBadge.colors
        )

        let stack = UIStackView(arrangedSubviews: [heading, standard, hyper])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(14, after: heading)
        stack.isAccessibilityElement = true
        stack.accessibilityLabel = String(localized: "Standard plays about 10 seconds behind the streamer, Hyper about 6 to 7.")
        return card(around: stack)
    }

    private func makeBar(title: String, value: String, fraction: CGFloat, fill: UIColor? = nil, gradient: [UIColor]? = nil) -> UIView {
        let name = UILabel()
        name.text = title
        name.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        name.adjustsFontForContentSizeCategory = true
        name.textColor = Theme.primaryText

        let amount = UILabel()
        amount.text = value
        amount.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .monospacedDigitSystemFont(ofSize: 15, weight: .medium))
        amount.adjustsFontForContentSizeCategory = true
        amount.textColor = Theme.secondaryText
        amount.setContentHuggingPriority(.required, for: .horizontal)

        let labels = UIStackView(arrangedSubviews: [name, amount])
        labels.axis = .horizontal
        labels.spacing = 8

        let track = UIView()
        track.backgroundColor = Theme.surfaceElevated
        track.layer.cornerRadius = 5
        track.layer.cornerCurve = .continuous
        track.clipsToBounds = true
        track.translatesAutoresizingMaskIntoConstraints = false
        track.heightAnchor.constraint(equalToConstant: 10).isActive = true

        let bar: UIView = gradient.map { GradientBarView(colors: $0) } ?? UIView()
        bar.backgroundColor = gradient == nil ? fill : nil
        bar.layer.cornerRadius = 5
        bar.layer.cornerCurve = .continuous
        bar.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(bar)
        let empty = bar.widthAnchor.constraint(equalToConstant: 0)
        let full = bar.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: fraction)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            bar.topAnchor.constraint(equalTo: track.topAnchor),
            bar.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            empty,
        ])
        bars.append((empty, full))

        let stack = UIStackView(arrangedSubviews: [labels, track])
        stack.axis = .vertical
        stack.spacing = 6
        return stack
    }

    /// Grows each bar from nothing to its share of the track once the sheet is on screen; at once with Reduce Motion.
    /// The share is a proportion of the track, so it holds through a change of detent or rotation.
    private func growBars() {
        view.layoutIfNeeded()
        for bar in bars {
            bar.empty.isActive = false
            bar.full.isActive = true
        }
        guard !Motion.reduced else {
            view.layoutIfNeeded()
            return
        }
        UIView.animate(withDuration: 0.9, delay: 0.1, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            self.view.layoutIfNeeded()
        }
    }

    /// The switch for a Founding Member, and for anyone else the offer it comes with; drawn again when either changes.
    private func renderAccess() {
        let member = supporter.isSupporter
        let on = member && store.current.hyperLowLatencyEnabled
        if toggle.isOn != on { toggle.setOn(on, animated: view.window != nil) }
        guard showsSwitch != member else { return }
        showsSwitch = member
        accessSlot.arrangedSubviews.forEach { $0.removeFromSuperview() }
        accessSlot.addArrangedSubview(member ? makeToggleCard() : makeOfferCard())
    }

    /// What a viewer without Founding Member sees where the switch would be: what Hyper comes with, and the way there.
    private func makeOfferCard() -> UIView {
        let title = UILabel()
        title.text = String(localized: "Comes with Founding Member")
        title.font = .preferredFont(forTextStyle: .body).withWeight(.semibold)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = Theme.primaryText
        title.numberOfLines = 0

        let detail = UILabel()
        detail.text = String(localized: "A one-time purchase that also brings themes, app icons, chat fonts and a badge everyone sees.")
        detail.font = .preferredFont(forTextStyle: .footnote)
        detail.adjustsFontForContentSizeCategory = true
        detail.textColor = Theme.secondaryText
        detail.numberOfLines = 0

        var config = UIButton.Configuration.filled()
        var label = AttributedString(String(localized: "See Founding Member"))
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        config.attributedTitle = label
        config.image = UIImage(systemName: "flame.fill")
        config.imagePadding = 6
        config.baseBackgroundColor = ExperimentalBadge.colors[0]
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self] _ in self?.presentFoundingMember() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, detail, button])
        stack.axis = .vertical
        stack.spacing = 4
        stack.setCustomSpacing(14, after: detail)
        return card(around: stack)
    }

    private func presentFoundingMember() {
        let page = SupporterViewController()
        let navigation = UINavigationController(rootViewController: page)
        page.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak navigation] _ in
            navigation?.dismiss(animated: true)
        })
        present(navigation, animated: true)
    }

    private func makeToggleCard() -> UIView {
        let title = UILabel()
        title.text = String(localized: "Hyper Low Latency")
        title.font = .preferredFont(forTextStyle: .body).withWeight(.semibold)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = Theme.primaryText
        title.numberOfLines = 0
        title.isAccessibilityElement = false

        let detail = UILabel()
        detail.text = String(localized: "Changes the stream that's playing right away.")
        detail.font = .preferredFont(forTextStyle: .footnote)
        detail.adjustsFontForContentSizeCategory = true
        detail.textColor = Theme.secondaryText
        detail.numberOfLines = 0
        detail.isAccessibilityElement = false

        let text = UIStackView(arrangedSubviews: [title, detail])
        text.axis = .vertical
        text.spacing = 2

        toggle.isOn = supporter.isSupporter && store.current.hyperLowLatencyEnabled
        toggle.onTintColor = ExperimentalBadge.colors[0]
        toggle.accessibilityLabel = String(localized: "Hyper Low Latency")
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let on = self.toggle.isOn
            self.store.update { $0.hyperLowLatency = on }
        }, for: .valueChanged)

        let row = UIStackView(arrangedSubviews: [text, toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        return card(around: row)
    }

    private func makeCard(_ topic: Topic) -> UIView {
        let badge = makeIconTile(symbol: topic.symbol, tint: topic.tint)

        let title = UILabel()
        title.text = topic.title
        title.font = .preferredFont(forTextStyle: .callout).withWeight(.semibold)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = Theme.primaryText
        title.numberOfLines = 0

        let body = UILabel()
        body.text = topic.body
        body.font = .preferredFont(forTextStyle: .subheadline)
        body.adjustsFontForContentSizeCategory = true
        body.textColor = Theme.secondaryText
        body.numberOfLines = 0

        let text = UIStackView(arrangedSubviews: [title, body])
        text.axis = .vertical
        text.spacing = 4

        let row = UIStackView(arrangedSubviews: [badge, text])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 14
        let wrapped = card(around: row)
        wrapped.isAccessibilityElement = true
        wrapped.accessibilityLabel = "\(topic.title). \(topic.body)"
        return wrapped
    }

    private func card(around content: UIView) -> UIView {
        let card = UIView()
        card.backgroundColor = Theme.surface
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
        ])
        return card
    }

    private func makeIconTile(symbol: String, tint: UIColor) -> UIView {
        let container = UIView()
        container.backgroundColor = tint.withAlphaComponent(0.16)
        container.layer.cornerRadius = 11
        container.layer.cornerCurve = .continuous
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setContentHuggingPriority(.required, for: .horizontal)

        let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)))
        icon.tintColor = tint
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(icon)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 40),
            container.heightAnchor.constraint(equalToConstant: 40),
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    private static func roundedBold(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    private func makeDoneButton() -> UIButton {
        var config = UIButton.Configuration.filled()
        var title = AttributedString(String(localized: "Done"))
        title.font = UIFont.preferredFont(forTextStyle: .headline)
        config.attributedTitle = title
        config.baseBackgroundColor = Theme.accent
        config.baseForegroundColor = Theme.onAccent
        config.cornerStyle = .large
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        return button
    }
}

/// A round tile in the badge's gradient with a bolt in it and a glow around it; the bolt breathes unless Reduce Motion is on.
@MainActor
private final class HyperOrbView: UIView {
    private let gradient = CAGradientLayer()
    private let bolt = UIImageView()
    private static let side: CGFloat = 76

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = false
        gradient.colors = ExperimentalBadge.colors.map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.cornerRadius = Self.side / 2
        gradient.masksToBounds = true
        layer.addSublayer(gradient)
        layer.shadowColor = ExperimentalBadge.colors[1].cgColor
        layer.shadowOpacity = 0.5
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 6)

        bolt.image = UIImage(systemName: "bolt.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .bold))
        bolt.tintColor = .white
        bolt.contentMode = .center
        bolt.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bolt)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.side),
            heightAnchor.constraint(equalToConstant: Self.side),
            bolt.centerXAnchor.constraint(equalTo: centerXAnchor),
            bolt.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        bolt.removeAllSymbolEffects()
        guard window != nil, !Motion.reduced else { return }
        bolt.addSymbolEffect(.breathe, options: .repeating)
    }
}

/// A bar filled with a left-to-right gradient.
@MainActor
private final class GradientBarView: UIView {
    override static var layerClass: AnyClass { CAGradientLayer.self }

    init(colors: [UIColor]) {
        super.init(frame: .zero)
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.colors = colors.map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// A strip that fades the cards out where they scroll under the Done button, in the sheet's own background color.
@MainActor
private final class ScrollFadeView: UIView {
    override static var layerClass: AnyClass { CAGradientLayer.self }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        applyColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ScrollFadeView, _) in view.applyColors() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func applyColors() {
        guard let gradient = layer as? CAGradientLayer else { return }
        let color = Theme.background.resolvedColor(with: traitCollection)
        gradient.colors = [color.withAlphaComponent(0).cgColor, color.cgColor]
    }
}
