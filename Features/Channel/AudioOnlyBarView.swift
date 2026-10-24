import UIKit
import EmbrCore

@MainActor
final class AudioOnlyBarView: UIView {
    var onPlayPause: (() -> Void)?
    var onRestoreVideo: (() -> Void)?

    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let titleLabel = UILabel()
    private let liveBadge = UIImageView()
    private let playPauseButton = UIButton(type: .system)
    private let restoreButton = UIButton(type: .system)

    init() {
        super.init(frame: .zero)
        isHidden = true
        backgroundColor = Theme.surface

        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 20
        avatarView.backgroundColor = Theme.surfaceElevated
        avatarView.image = UIImage(systemName: "person.crop.circle.fill")
        avatarView.tintColor = Theme.secondaryText

        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        nameLabel.textColor = Theme.primaryText

        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = Theme.secondaryText
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        let badgeConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        liveBadge.image = UIImage(systemName: "dot.radiowaves.left.and.right", withConfiguration: badgeConfig)
        liveBadge.tintColor = Theme.liveDot
        liveBadge.contentMode = .scaleAspectFit
        liveBadge.setContentHuggingPriority(.required, for: .horizontal)
        liveBadge.isAccessibilityElement = true
        liveBadge.accessibilityLabel = String(localized: "Live")

        let nameRow = UIStackView(arrangedSubviews: [nameLabel, liveBadge, UIView()])
        nameRow.axis = .horizontal
        nameRow.spacing = 6
        nameRow.alignment = .center

        let textStack = UIStackView(arrangedSubviews: [nameRow, titleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.lineBreakMode = .byTruncatingTail

        configureButton(playPauseButton, symbol: "pause.fill", label: String(localized: "Pause"))
        playPauseButton.addAction(UIAction { [weak self] _ in self?.onPlayPause?() }, for: .touchUpInside)
        configureButton(restoreButton, symbol: "play.rectangle.fill", label: String(localized: "Show Video"))
        restoreButton.addAction(UIAction { [weak self] _ in self?.onRestoreVideo?() }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [avatarView, textStack, playPauseButton, restoreButton])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 8)
        addSubview(row)

        let separator = UIView()
        separator.backgroundColor = Theme.surfaceElevated
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        let separatorHeight = separator.heightAnchor.constraint(equalToConstant: 1.0 / max(traitCollection.displayScale, 1))
        registerForTraitChanges([UITraitDisplayScale.self]) { (bar: AudioOnlyBarView, _) in
            separatorHeight.constant = 1.0 / max(bar.traitCollection.displayScale, 1)
        }

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separatorHeight
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func configureButton(_ button: UIButton, symbol: String, label: String) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        config.baseForegroundColor = Theme.accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        button.configuration = config
        button.accessibilityLabel = label
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    func configure(name: String, title: String) {
        nameLabel.text = name
        titleLabel.text = title
    }

    func setAvatar(_ image: UIImage?) {
        guard let image else { return }
        avatarView.image = image
    }

    func setPlaying(_ playing: Bool) {
        var config = playPauseButton.configuration ?? .plain()
        config.image = UIImage(
            systemName: playing ? "pause.fill" : "play.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        )
        playPauseButton.configuration = config
        playPauseButton.accessibilityLabel = playing ? String(localized: "Pause") : String(localized: "Play")
        if playing, !Motion.reduced {
            liveBadge.addSymbolEffect(.variableColor.iterative, options: .repeating)
        } else {
            liveBadge.removeAllSymbolEffects()
        }
    }
}
