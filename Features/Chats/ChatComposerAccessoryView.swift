import UIKit

/// The chat composer folded into the tab bar's accessory, sharing the tab bar's glass: the field's placeholder, or the
/// unsent draft, with the emote button beside it. Tapping it opens the full composer above the keyboard; signed out it
/// offers to log in.
@MainActor
final class ChatComposerAccessoryView: UIView {
    /// Asked to open the composer, on the emote keyboard when the emote button was tapped.
    var onCompose: ((Bool) -> Void)?

    private let fieldButton = UIButton(type: .system)
    private let emoteButton = UIButton(type: .system)
    private var canCompose = true
    private var shown: (text: String, isDraft: Bool) = ("", false)

    override init(frame: CGRect) {
        super.init(frame: frame)
        fieldButton.contentHorizontalAlignment = .fill
        fieldButton.addAction(UIAction { [weak self] _ in
            Haptics.selection()
            self?.onCompose?(false)
        }, for: .primaryActionTriggered)
        fieldButton.accessibilityCustomActions = [UIAccessibilityCustomAction(name: String(localized: "Emotes")) { [weak self] _ in
            self?.onCompose?(true)
            return true
        }]

        var emote = UIButton.Configuration.plain()
        emote.image = UIImage(systemName: "face.smiling", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular))
        emote.baseForegroundColor = Theme.secondaryText
        emoteButton.configuration = emote
        emoteButton.accessibilityLabel = String(localized: "Emotes")
        emoteButton.addAction(UIAction { [weak self] _ in
            Haptics.selection()
            self?.onCompose?(true)
        }, for: .primaryActionTriggered)

        let row = UIStackView(arrangedSubviews: [fieldButton, emoteButton])
        row.axis = .horizontal
        row.alignment = .fill
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            emoteButton.widthAnchor.constraint(equalToConstant: 44),
        ])
        if #available(iOS 26.0, *) {
            registerForTraitChanges([UITraitTabAccessoryEnvironment.self]) { (view: ChatComposerAccessoryView, _) in
                view.applyEnvironment()
            }
        }
        styleField()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Shows the unsent draft when there is one, the composer's placeholder otherwise.
    func show(placeholder: String, draft: String, canCompose: Bool) {
        self.canCompose = canCompose
        shown = draft.isEmpty ? (placeholder, false) : (draft, true)
        styleField()
        applyEnvironment()
        fieldButton.accessibilityLabel = shown.isDraft ? String(localized: "Draft: \(draft)") : placeholder
        fieldButton.accessibilityHint = canCompose ? String(localized: "Opens the message field") : nil
    }

    #if DEBUG
    /// Taps the field the way a finger does, from the point at its center, for checking the folded composer opens.
    func tapFieldForTesting() -> Bool {
        let center = fieldButton.convert(CGPoint(x: fieldButton.bounds.midX, y: fieldButton.bounds.midY), to: nil)
        guard let hit = window?.hitTest(center, with: nil), hit === fieldButton || hit.isDescendant(of: fieldButton) else { return false }
        fieldButton.sendActions(for: .primaryActionTriggered)
        return true
    }
    #endif

    /// The field reads like the composer's own: placeholder gray or the draft in full color, then Log In in the accent
    /// when signed out. A button, so a tap anywhere on it opens the composer with the system's press feedback.
    private func styleField() {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 8)
        config.titleLineBreakMode = .byTruncatingTail
        var title = AttributedString(shown.text)
        title.font = UIFont.preferredFont(forTextStyle: .body)
        title.foregroundColor = shown.isDraft ? Theme.primaryText : UIColor.placeholderText
        if !canCompose {
            var login = AttributedString("  " + String(localized: "Log In"))
            login.font = UIFont.preferredFont(forTextStyle: .body).withWeight(.semibold)
            login.foregroundColor = Theme.accent
            title += login
        }
        config.attributedTitle = title
        config.titleAlignment = .leading
        fieldButton.configuration = config
        fieldButton.contentHorizontalAlignment = .leading
    }

    /// Inline beside a minimized tab bar there is room only for the field.
    private func applyEnvironment() {
        var inline = false
        if #available(iOS 26.0, *) {
            inline = traitCollection.tabAccessoryEnvironment == .inline
        }
        emoteButton.isHidden = inline || !canCompose
    }
}
