import AVKit
import UIKit
import EmbrCore

/// The compact player above chat: the channel with play and pause, the AirPlay picker and a button back to the video.
/// It stands in for the video while audio plays alone, or while a TV plays the stream and the page shows only chat.
@MainActor
final class MiniPlayerBarView: UIView {
    var onPlayPause: (() -> Void)?
    var onRestoreVideo: (() -> Void)?

    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let liveBadge = UIImageView()
    private let playPauseButton = UIButton(type: .system)
    private let routePicker = AVRoutePickerView()
    private let restoreButton = UIButton(type: .system)
    private var streamTitle = ""
    private var externalRoute: ExternalRoute?

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

        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = Theme.secondaryText
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail

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

        let textStack = UIStackView(arrangedSubviews: [nameRow, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureButton(playPauseButton, symbol: "pause.fill", label: String(localized: "Pause"))
        playPauseButton.addAction(UIAction { [weak self] _ in self?.onPlayPause?() }, for: .touchUpInside)
        configureRoutePicker()
        configureButton(restoreButton, symbol: "play.rectangle.fill", label: String(localized: "Show Video"))
        restoreButton.addAction(UIAction { [weak self] _ in self?.onRestoreVideo?() }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [avatarView, textStack, playPauseButton, routePicker, restoreButton])
        row.axis = .horizontal
        row.spacing = 8
        row.setCustomSpacing(12, after: avatarView)
        row.setCustomSpacing(4, after: textStack)
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
        registerForTraitChanges([UITraitDisplayScale.self]) { (bar: MiniPlayerBarView, _) in
            separatorHeight.constant = 1.0 / max(bar.traitCollection.displayScale, 1)
        }

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),
            routePicker.widthAnchor.constraint(equalToConstant: 38),
            routePicker.heightAnchor.constraint(equalToConstant: 38),
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
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func configureRoutePicker() {
        routePicker.tintColor = Theme.accent
        routePicker.activeTintColor = Theme.accent
        routePicker.prioritizesVideoDevices = true
        routePicker.translatesAutoresizingMaskIntoConstraints = false
        routePicker.setContentHuggingPriority(.required, for: .horizontal)
        routePicker.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    /// Tops `stack` while it is shown and leaves it otherwise: the page above chat, or the stream details beside chat on a
    /// foldable open like a book.
    func place(atTopOf stack: UIStackView, shown: Bool) {
        guard shown else {
            isHidden = true
            removeFromSuperview()
            return
        }
        if superview !== stack {
            stack.insertArrangedSubview(self, at: 0)
        }
        isHidden = false
    }

    func configure(name: String, title: String) {
        nameLabel.text = name
        streamTitle = title
        applySubtitle()
    }

    /// While a TV plays the stream the bar says which one, in the accent color, in place of the stream title.
    func setExternalRoute(_ route: ExternalRoute?) {
        guard route != externalRoute else { return }
        externalRoute = route
        applySubtitle()
    }

    private func applySubtitle() {
        guard let externalRoute else {
            subtitleLabel.attributedText = nil
            subtitleLabel.text = streamTitle
            subtitleLabel.textColor = Theme.secondaryText
            subtitleLabel.accessibilityLabel = nil
            return
        }
        let text = externalRoute.playingOnText
        let glyph = UIImage(systemName: "airplay.video", withConfiguration: UIImage.SymbolConfiguration(font: subtitleLabel.font))
        let subtitle = NSMutableAttributedString()
        if let glyph {
            subtitle.append(NSAttributedString(attachment: NSTextAttachment(image: glyph)))
            subtitle.append(NSAttributedString(string: " "))
        }
        subtitle.append(NSAttributedString(string: text))
        subtitle.addAttribute(.foregroundColor, value: Theme.accent, range: NSRange(location: 0, length: subtitle.length))
        subtitleLabel.attributedText = subtitle
        subtitleLabel.accessibilityLabel = text
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
