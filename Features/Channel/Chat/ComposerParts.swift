import UIKit

/// The composer's send button: a filled accent circle with an arrow once there is something to send, a quiet gray
/// one before, a spinner while the message goes out, and the seconds left while slow mode holds the next message.
@MainActor
final class SendButton: UIControl {
    enum Mode: Equatable {
        case empty
        case ready
        case sending
        case cooldown(Int)
    }

    private(set) var mode: Mode = .empty
    private let circle = UIView()
    private let arrow = UIImageView()
    private let countdown = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        circle.isUserInteractionEnabled = false
        circle.layer.cornerRadius = ChatMetrics.sendDiameter / 2
        circle.layer.cornerCurve = .circular
        circle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(circle)
        arrow.image = UIImage(systemName: "arrow.up")
        arrow.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        arrow.contentMode = .center
        arrow.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(arrow)
        countdown.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        countdown.textAlignment = .center
        countdown.textColor = Theme.secondaryText
        countdown.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(countdown)
        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(spinner)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: ChatMetrics.field),
            heightAnchor.constraint(equalToConstant: ChatMetrics.field),
            circle.centerXAnchor.constraint(equalTo: centerXAnchor),
            circle.centerYAnchor.constraint(equalTo: centerYAnchor),
            circle.widthAnchor.constraint(equalToConstant: ChatMetrics.sendDiameter),
            circle.heightAnchor.constraint(equalToConstant: ChatMetrics.sendDiameter),
            arrow.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            arrow.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            countdown.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            countdown.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: circle.centerYAnchor)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        largeContentImage = UIImage(systemName: "arrow.up.circle.fill")
        showsLargeContentViewer = true
        apply(.empty, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setMode(_ next: Mode) {
        guard next != mode else { return }
        let popsIn = mode == .empty && next == .ready
        apply(next, animated: window != nil)
        if popsIn, !Motion.reduced {
            circle.transform = CGAffineTransform(scaleX: 0.72, y: 0.72)
            UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.6, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.circle.transform = .identity
            }
        }
    }

    private func apply(_ next: Mode, animated: Bool) {
        mode = next
        isEnabled = next == .ready
        let filled = next == .ready || next == .sending
        let changes = {
            self.circle.backgroundColor = filled ? Theme.accent : .tertiarySystemFill
            self.arrow.tintColor = filled ? Theme.onAccent : .tertiaryLabel
            self.arrow.alpha = (next == .ready || next == .empty) ? 1 : 0
            self.countdown.alpha = { if case .cooldown = next { return 1 } else { return 0 } }()
        }
        if case .cooldown(let seconds) = next { countdown.text = "\(seconds)" }
        spinner.color = Theme.onAccent
        if next == .sending { spinner.startAnimating() } else { spinner.stopAnimating() }
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
        } else {
            changes()
        }
        switch next {
        case .empty, .ready: accessibilityLabel = String(localized: "Send")
        case .sending: accessibilityLabel = String(localized: "Sending")
        case .cooldown(let seconds): accessibilityLabel = String(localized: "Slow mode, \(seconds) seconds")
        }
        largeContentTitle = accessibilityLabel
    }

    override var isHighlighted: Bool {
        didSet {
            guard isEnabled, !Motion.reduced else { return }
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.circle.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.88, y: 0.88) : .identity
            }
        }
    }
}

/// The emote button inside the composer field: a smiley that turns into a keyboard while the emote keyboard is up.
@MainActor
final class EmoteToggleButton: UIControl {
    private let icon = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
        icon.tintColor = Theme.secondaryText
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        showsLargeContentViewer = true
        setShowsKeyboard(false, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setShowsKeyboard(_ showsKeyboard: Bool, animated: Bool) {
        let image = UIImage(systemName: showsKeyboard ? "keyboard" : "face.smiling")
        if let image {
            if animated, !Motion.reduced {
                icon.setSymbolImage(image, contentTransition: .replace.downUp)
            } else {
                icon.image = image
            }
        }
        icon.tintColor = showsKeyboard ? Theme.accent : Theme.secondaryText
        accessibilityLabel = showsKeyboard ? String(localized: "Keyboard") : String(localized: "Emotes")
        largeContentTitle = accessibilityLabel
        largeContentImage = image
    }

    override var isHighlighted: Bool {
        didSet { icon.alpha = isHighlighted ? 0.5 : 1 }
    }
}

/// The strip above the composer while replying: an accent bar, who the reply goes to and what they said, and a
/// button to stop replying.
@MainActor
final class ReplyComposerBar: UIView {
    var onCancel: (() -> Void)?
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let cancelButton = UIButton(type: .system)

    init() {
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(displayName: String, text: String) {
        titleLabel.text = String(localized: "Replying to \(displayName)")
        bodyLabel.text = text
        accessibilityLabel = String(localized: "Replying to \(displayName): \(text)")
    }

    private func setUp() {
        let bar = UIView()
        bar.backgroundColor = Theme.accent
        bar.layer.cornerRadius = 1.5
        bar.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .preferredFont(forTextStyle: .footnote).withWeight(.semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.accent
        bodyLabel.font = .preferredFont(forTextStyle: .footnote)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.textColor = Theme.secondaryText
        bodyLabel.numberOfLines = 1

        let labels = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        labels.axis = .vertical
        labels.spacing = 1

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular))
        config.baseForegroundColor = .tertiaryLabel
        config.contentInsets = .zero
        cancelButton.configuration = config
        cancelButton.accessibilityLabel = String(localized: "Cancel Reply")
        cancelButton.addAction(UIAction { [weak self] _ in
            Haptics.selection()
            self?.onCancel?()
        }, for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [bar, labels, cancelButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: ChatMetrics.composerVertical, leading: ChatMetrics.edge, bottom: 0, trailing: ChatMetrics.edge - (ChatMetrics.field - ChatMetrics.sendDiameter) / 2)
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.widthAnchor.constraint(equalToConstant: 3),
            bar.heightAnchor.constraint(equalTo: labels.heightAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: ChatMetrics.field),
            cancelButton.heightAnchor.constraint(equalToConstant: ChatMetrics.field)
        ])
    }
}

extension UIFont {
    /// The same font at another weight, keeping its Dynamic Type scaling.
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: 0)
    }
}
