import UIKit

/// Educational sheet, opened from the ad-break cover, explaining why ads appear
/// in Embr even for Twitch Turbo subscribers.
@MainActor
final class AdInfoViewController: UIViewController {

    private struct Topic {
        let symbol: String
        let tint: UIColor
        let title: String
        let body: String
    }

    private static let topics: [Topic] = [
        Topic(
            symbol: "antenna.radiowaves.left.and.right",
            tint: .systemTeal,
            title: "Ads are stitched into the stream",
            body: "Twitch uses server-side ad insertion: the ad video is spliced directly into the live stream's segments on Twitch's own servers, mixed in with the broadcast. By the time the stream reaches Embr the ad is already baked in — it isn't a separate track a player can simply switch off."
        ),
        Topic(
            symbol: "scissors",
            tint: Theme.accent,
            title: "Embr cuts the ads out",
            body: "Embr detects those stitched-ad segments and drops them before they play. Instead of watching the ad you get a brief \"resuming shortly\" gap, because Twitch is still sending ad content during that window and there's nothing else to show. That gap is exactly when Embr Flyer appears."
        ),
        Topic(
            symbol: "crown.fill",
            tint: .systemOrange,
            title: "Why Turbo or a sub doesn't skip them here",
            body: "Turbo's ad-free perk is tied to your account inside Twitch's own apps, applied the moment the official player requests a stream. Embr connects as an independent client and can't hand that entitlement to Twitch's ad system. Third-party clients used to forward a web login to request an ad-free stream, but Twitch closed that path — today the playback handshake returns \"ads on\" for everyone: Turbo members, subscribers, and logged-out viewers alike."
        ),
        Topic(
            symbol: "heart.fill",
            tint: .systemPink,
            title: "Supporting your streamer still matters",
            body: "A subscription still goes to your streamer and unlocks their emotes and badges, even though it can't remove ads inside Embr. If ad-free viewing is what you're after, the official Twitch app honors your Turbo subscription."
        )
    ]

    init() {
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
    }

    private func build() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        stack.addArrangedSubview(makeHeader())
        stack.setCustomSpacing(22, after: stack.arrangedSubviews[0])
        for topic in Self.topics { stack.addArrangedSubview(makeCard(topic)) }
        stack.addArrangedSubview(makeDisclaimer())

        let dismissButton = makeDismissButton()
        view.addSubview(dismissButton)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: dismissButton.topAnchor, constant: -8),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),

            dismissButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            dismissButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            dismissButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            dismissButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func makeHeader() -> UIView {
        let badge = makeIconBadge(symbol: "megaphone.fill", tint: Theme.accent, size: 56, pointSize: 26)

        let title = UILabel()
        title.text = "Why am I seeing ads?"
        title.font = .systemFont(ofSize: 26, weight: .bold)
        title.textColor = Theme.primaryText
        title.numberOfLines = 0

        let subtitle = UILabel()
        subtitle.text = "Even with Twitch Turbo or a channel sub — here's what's happening."
        subtitle.font = .systemFont(ofSize: 15, weight: .regular)
        subtitle.textColor = Theme.secondaryText
        subtitle.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [badge, title, subtitle])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(16, after: badge)
        stack.setCustomSpacing(6, after: title)
        return stack
    }

    private func makeCard(_ topic: Topic) -> UIView {
        let badge = makeIconBadge(symbol: topic.symbol, tint: topic.tint, size: 40, pointSize: 18)
        badge.setContentHuggingPriority(.required, for: .horizontal)

        let title = UILabel()
        title.text = topic.title
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = Theme.primaryText
        title.numberOfLines = 0

        let body = UILabel()
        body.text = topic.body
        body.font = .systemFont(ofSize: 14, weight: .regular)
        body.textColor = Theme.secondaryText
        body.numberOfLines = 0

        let text = UIStackView(arrangedSubviews: [title, body])
        text.axis = .vertical
        text.spacing = 4

        let row = UIStackView(arrangedSubviews: [badge, text])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 14

        let card = UIView()
        card.backgroundColor = Theme.surface
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)
        ])
        return card
    }

    private func makeDisclaimer() -> UIView {
        let label = UILabel()
        label.text = "Embr is an independent, open-source client and isn't affiliated with Twitch. Ad handling is provided for personal use."
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = Theme.secondaryText
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }

    private func makeIconBadge(symbol: String, tint: UIColor, size: CGFloat, pointSize: CGFloat) -> UIView {
        let container = UIView()
        container.backgroundColor = tint.withAlphaComponent(0.16)
        container.layer.cornerRadius = size * 0.28
        container.layer.cornerCurve = .continuous
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)))
        icon.tintColor = tint
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(icon)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: size),
            container.heightAnchor.constraint(equalToConstant: size),
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func makeDismissButton() -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = "Got it"
        config.baseBackgroundColor = Theme.accent
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        var title = AttributedString("Got it")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        config.attributedTitle = title
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        return button
    }
}
