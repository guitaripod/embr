import UIKit

/// The chat composer folded into the tab bar's accessory, sharing the tab bar's glass: the field's placeholder, or the
/// unsent draft, with the emote button beside it. Tapping it opens the full composer above the keyboard; signed out it
/// offers to log in.
@MainActor
final class ChatComposerAccessoryView: UIControl {
    /// Asked to open the composer, on the emote keyboard when the emote button was tapped.
    var onCompose: ((Bool) -> Void)?

    private let label = UILabel()
    private let emoteButton = UIButton(type: .system)
    private let loginLabel = UILabel()
    private var canCompose = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.lineBreakMode = .byTruncatingTail
        label.isUserInteractionEnabled = false

        var emote = UIButton.Configuration.plain()
        emote.image = UIImage(systemName: "face.smiling", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular))
        emote.baseForegroundColor = Theme.secondaryText
        emoteButton.configuration = emote
        emoteButton.accessibilityLabel = String(localized: "Emotes")
        emoteButton.addAction(UIAction { [weak self] _ in
            Haptics.selection()
            self?.onCompose?(true)
        }, for: .primaryActionTriggered)

        loginLabel.text = String(localized: "Log In")
        loginLabel.font = .preferredFont(forTextStyle: .body).withWeight(.semibold)
        loginLabel.adjustsFontForContentSizeCategory = true
        loginLabel.textColor = Theme.accent
        loginLabel.isHidden = true
        loginLabel.isUserInteractionEnabled = false

        let row = UIStackView(arrangedSubviews: [label, loginLabel, emoteButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            emoteButton.widthAnchor.constraint(equalToConstant: 44),
            emoteButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        loginLabel.setContentHuggingPriority(.required, for: .horizontal)

        addAction(UIAction { [weak self] _ in
            Haptics.selection()
            self?.onCompose?(false)
        }, for: .primaryActionTriggered)
        isAccessibilityElement = true
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: String(localized: "Emotes")) { [weak self] _ in
            self?.onCompose?(true)
            return true
        }]
        if #available(iOS 26.0, *) {
            registerForTraitChanges([UITraitTabAccessoryEnvironment.self]) { (view: ChatComposerAccessoryView, _) in
                view.applyEnvironment()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Shows the unsent draft when there is one, the composer's placeholder otherwise.
    func show(placeholder: String, draft: String, canCompose: Bool) {
        self.canCompose = canCompose
        let hasDraft = !draft.isEmpty
        label.text = hasDraft ? draft : placeholder
        label.textColor = hasDraft ? Theme.primaryText : .placeholderText
        loginLabel.isHidden = canCompose
        applyEnvironment()
        accessibilityLabel = hasDraft ? String(localized: "Draft: \(draft)") : placeholder
        accessibilityHint = canCompose ? String(localized: "Opens the message field") : nil
        accessibilityTraits = .button
    }

    /// Inline beside a minimized tab bar there is room only for the field.
    private func applyEnvironment() {
        var inline = false
        if #available(iOS 26.0, *) {
            inline = traitCollection.tabAccessoryEnvironment == .inline
        }
        emoteButton.isHidden = inline || !canCompose
    }

    override var isHighlighted: Bool {
        didSet { label.alpha = isHighlighted ? 0.5 : 1 }
    }
}
