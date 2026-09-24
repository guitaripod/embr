import UIKit
import EmbrCore

/// The broadcaster's own description, shown under the stream details on iPad when the video
/// sits beside the chat column and leaves room below it.
@MainActor
final class ChannelAboutView: UIView {
    var onShowVideos: (() -> Void)?

    private let card = UIView()
    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private let typeLabel = UILabel()
    private let joinedLabel = UILabel()
    private let bioLabel = UILabel()
    private let videosButton = UIButton(type: .system)

    private(set) var hasContent = false

    init() {
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(user: TwitchUser) {
        hasContent = true
        nameLabel.text = user.displayName
        switch user.broadcasterType {
        case "partner": typeLabel.text = String(localized: "TWITCH PARTNER")
        case "affiliate": typeLabel.text = String(localized: "AFFILIATE")
        default: typeLabel.text = nil
        }
        typeLabel.isHidden = typeLabel.text == nil
        let bio = user.description.trimmingCharacters(in: .whitespacesAndNewlines)
        bioLabel.text = bio
        bioLabel.isHidden = bio.isEmpty
        if let createdAt = user.createdAt {
            joinedLabel.text = String(localized: "On Twitch since \(createdAt.formatted(.dateTime.year()))")
            joinedLabel.isHidden = false
        } else {
            joinedLabel.isHidden = true
        }
    }

    func setAvatar(_ image: UIImage?) {
        guard let image else { return }
        avatar.image = image
    }

    private func setUp() {
        card.backgroundColor = Theme.surface
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 24
        avatar.backgroundColor = Theme.surfaceElevated
        avatar.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 17, weight: .semibold))
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = Theme.primaryText

        typeLabel.font = .systemFont(ofSize: 10, weight: .heavy)
        typeLabel.textColor = Theme.accent
        typeLabel.setContentHuggingPriority(.required, for: .horizontal)

        joinedLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12))
        joinedLabel.adjustsFontForContentSizeCategory = true
        joinedLabel.textColor = Theme.secondaryText

        bioLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 14))
        bioLabel.adjustsFontForContentSizeCategory = true
        bioLabel.textColor = Theme.secondaryText
        bioLabel.numberOfLines = 4

        var config = UIButton.Configuration.tinted()
        config.title = String(localized: "Videos & Clips")
        config.image = UIImage(systemName: "film.stack")
        config.imagePadding = 6
        config.cornerStyle = .capsule
        config.buttonSize = .small
        config.baseForegroundColor = Theme.accent
        videosButton.configuration = config
        videosButton.addAction(UIAction { [weak self] _ in self?.onShowVideos?() }, for: .touchUpInside)

        let nameRow = UIStackView(arrangedSubviews: [nameLabel, typeLabel, UIView()])
        nameRow.axis = .horizontal
        nameRow.spacing = 8
        nameRow.alignment = .firstBaseline

        let identity = UIStackView(arrangedSubviews: [nameRow, joinedLabel])
        identity.axis = .vertical
        identity.spacing = 2

        identity.setContentHuggingPriority(.defaultLow, for: .horizontal)
        videosButton.setContentHuggingPriority(.required, for: .horizontal)
        videosButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        let header = UIStackView(arrangedSubviews: [avatar, identity, videosButton])
        header.axis = .horizontal
        header.spacing = 12
        header.alignment = .center

        let stack = UIStackView(arrangedSubviews: [header, bioLabel])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            avatar.widthAnchor.constraint(equalToConstant: 48),
            avatar.heightAnchor.constraint(equalToConstant: 48)
        ])

        isAccessibilityElement = false
        card.accessibilityElements = [nameLabel, typeLabel, joinedLabel, bioLabel, videosButton]
    }
}
