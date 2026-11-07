import UIKit
import EmbrCore

/// The slim bar above a moderator's composer: how many messages AutoMod holds and unban requests wait, or the log's
/// length when nothing waits. Tapping it opens the queue.
@MainActor
final class ModerationBar: UIButton {
    static let height: CGFloat = 34
    var onOpen: (() -> Void)?

    private let icon = UIImageView(image: UIImage(systemName: "shield.lefthalf.filled"))
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.surface
        clipsToBounds = true
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .footnote, scale: .medium)
        icon.tintColor = Theme.accent
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Theme.primaryText
        let chevron = UIImageView(image: UIImage(systemName: "chevron.up"))
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption2, scale: .small)
        chevron.tintColor = Theme.secondaryText
        let row = UIStackView(arrangedSubviews: [icon, label, UIView(), chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ChatMetrics.edge),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ChatMetrics.edge),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        addAction(UIAction { [weak self] _ in self?.onOpen?() }, for: .primaryActionTriggered)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(held: Int, requests: Int, logged: Int) {
        var parts: [String] = []
        if held > 0 { parts.append(String(localized: "AutoMod: \(held) held")) }
        if requests > 0 { parts.append(String(localized: "Unban requests: \(requests)")) }
        label.text = parts.isEmpty ? String(localized: "Moderation log: \(logged)") : parts.joined(separator: " · ")
        label.font = .preferredFont(forTextStyle: .footnote)
        icon.tintColor = parts.isEmpty ? Theme.secondaryText : Theme.accent
        accessibilityLabel = label.text
    }
}

@MainActor
final class ConnectionStatusBar: UIView {
    var onTapReconnect: (() -> Void)?

    private let icon = UIImageView()
    private let label = UILabel()
    private let roomStateLabel = UILabel()
    private let statusRow = UIStackView()
    private var noticeDismiss: DispatchWorkItem?
    private var lastStatus: ConnectionStatus = .idle
    private var canReconnect = false

    init() {
        super.init(frame: .zero)
        setUp()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleTap() {
        guard canReconnect else { return }
        onTapReconnect?()
    }

    func showNotice(_ notice: SystemNotice) {
        show(
            text: notice.text,
            symbol: notice.isError ? "exclamationmark.triangle.fill" : "info.circle",
            pulse: false,
            color: notice.isError ? .systemRed : Theme.secondaryText
        )
        noticeDismiss?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.noticeDismiss = nil
            self.applyStatus(self.lastStatus)
        }
        noticeDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    func update(_ status: ConnectionStatus) {
        lastStatus = status
        noticeDismiss?.cancel()
        noticeDismiss = nil
        applyStatus(status)
    }

    private func applyStatus(_ status: ConnectionStatus) {
        canReconnect = false
        switch status {
        case .idle, .connected:
            statusRow.isHidden = true
            icon.removeAllSymbolEffects()
            updateContainerVisibility()
        case .connecting:
            show(text: String(localized: "Connecting…"), symbol: "dot.radiowaves.left.and.right", pulse: true, color: Theme.slowMode)
        case .reconnecting(let attempt):
            show(text: String(localized: "Reconnecting (\(attempt))…"), symbol: "arrow.triangle.2.circlepath", pulse: true, color: Theme.slowMode)
        case .disconnected(let reason):
            canReconnect = true
            show(text: reason ?? String(localized: "Disconnected · Tap to reconnect"), symbol: "arrow.clockwise", pulse: false, color: .systemRed)
        }
    }

    func update(roomState: RoomState) {
        var parts: [String] = []
        if roomState.emoteOnly { parts.append(String(localized: "Emote-only")) }
        if roomState.subscribersOnly { parts.append(String(localized: "Subs-only")) }
        if let seconds = roomState.followersOnly {
            parts.append(seconds == 0 ? String(localized: "Followers-only") : String(localized: "Followers \(seconds)m"))
        }
        if let slow = roomState.slowMode { parts.append(String(localized: "Slow \(slow)s")) }
        if roomState.uniqueChat { parts.append(String(localized: "Unique")) }
        roomStateLabel.text = parts.joined(separator: " · ")
        roomStateLabel.isHidden = parts.isEmpty
        updateContainerVisibility()
    }

    private func show(text: String, symbol: String, pulse: Bool, color: UIColor) {
        statusRow.isHidden = false
        label.text = text
        label.textColor = color
        icon.image = UIImage(systemName: symbol)
        icon.tintColor = color
        icon.removeAllSymbolEffects()
        if pulse, !Motion.reduced { icon.addSymbolEffect(.pulse, options: .repeating) }
        updateContainerVisibility()
    }

    private func updateContainerVisibility() {
        isHidden = statusRow.isHidden && roomStateLabel.isHidden
    }

    private func setUp() {
        if Glass.isAvailable {
            backgroundColor = .clear
            let glass = Glass.view()
            addSubview(glass)
            NSLayoutConstraint.activate([
                glass.topAnchor.constraint(equalTo: topAnchor),
                glass.bottomAnchor.constraint(equalTo: bottomAnchor),
                glass.leadingAnchor.constraint(equalTo: leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        } else {
            backgroundColor = Theme.surface.withAlphaComponent(0.95)
        }
        icon.contentMode = .scaleAspectFit
        label.font = .systemFont(ofSize: 13, weight: .medium)
        roomStateLabel.font = .systemFont(ofSize: 11, weight: .regular)
        roomStateLabel.textColor = Theme.secondaryText
        roomStateLabel.isHidden = true

        statusRow.addArrangedSubview(icon)
        statusRow.addArrangedSubview(label)
        statusRow.axis = .horizontal
        statusRow.spacing = 6
        statusRow.alignment = .center
        statusRow.isHidden = true

        let stack = UIStackView(arrangedSubviews: [statusRow, roomStateLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: ChatMetrics.edge, bottom: 6, trailing: ChatMetrics.edge)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16)
        ])
    }
}

@MainActor
final class NewMessagesPill: UIControl {
    var onTap: (() -> Void)?
    private let label = UILabel()
    private let icon = UIImageView()

    init() {
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setCount(_ count: Int) {
        label.text = count == 1 ? String(localized: "1 new message") : String(localized: "\(count) new messages")
        accessibilityLabel = label.text
    }

    /// Rises in from below with a little spring, and drops away when the chat is back at the newest message.
    func setShown(_ shown: Bool) {
        guard shown == isHidden else { return }
        guard window != nil, !Motion.reduced else {
            isHidden = !shown
            return
        }
        if shown {
            isHidden = false
            alpha = 0
            transform = CGAffineTransform(translationX: 0, y: 12).scaledBy(x: 0.92, y: 0.92)
        }
        UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.alpha = shown ? 1 : 0
            self.transform = shown ? .identity : CGAffineTransform(translationX: 0, y: 12).scaledBy(x: 0.92, y: 0.92)
        } completion: { _ in
            if !shown, self.alpha == 0 { self.isHidden = true }
        }
    }

    private func setUp() {
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = String(localized: "Jumps to the newest message")

        if Glass.isAvailable {
            backgroundColor = .clear
            let glass = Glass.view(cornerRadius: 18, tint: Theme.accent, interactive: true)
            glass.isUserInteractionEnabled = false
            addSubview(glass)
            NSLayoutConstraint.activate([
                glass.topAnchor.constraint(equalTo: topAnchor),
                glass.bottomAnchor.constraint(equalTo: bottomAnchor),
                glass.leadingAnchor.constraint(equalTo: leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        } else {
            backgroundColor = Theme.accent
        }

        icon.image = UIImage(systemName: "arrow.down")
        icon.tintColor = Theme.onAccent
        icon.contentMode = .scaleAspectFit

        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = Theme.onAccent

        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.spacing = 6
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 16)
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
    }

    @objc private func tapped() {
        onTap?()
    }
}

@MainActor
final class GuestChatBar: UIView {
    var onLogin: (() -> Void)?
    private let loginButton = UIButton(type: .system)

    init() {
        super.init(frame: .zero)
        backgroundColor = Theme.surface

        let icon = UIImageView(image: UIImage(systemName: "bubble.left.and.bubble.right"))
        icon.tintColor = Theme.secondaryText
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = String(localized: "Log in to chat")
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = Theme.secondaryText

        var configuration = UIButton.Configuration.tinted()
        configuration.title = String(localized: "Log In")
        configuration.cornerStyle = .large
        configuration.baseForegroundColor = Theme.accent
        loginButton.configuration = configuration
        loginButton.setContentHuggingPriority(.required, for: .horizontal)
        loginButton.addAction(UIAction { [weak self] _ in self?.onLogin?() }, for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [icon, label, loginButton])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: ChatMetrics.composerVertical, leading: ChatMetrics.edge, bottom: ChatMetrics.composerVertical, trailing: ChatMetrics.edge)
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
