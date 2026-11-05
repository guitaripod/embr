import UIKit
import EmbrCore

/// Three chat messages drawn by the real chat renderer, one of them the viewer's own with the supporter look they have
/// or are trying on: the badge, the name color or glow and the chat font, exactly as chat will show them.
final class SupporterChatPreview: UIView {
    private static let ownID = "embr-preview-self"

    private let card = UIView()
    private let header = UILabel()
    private var cells: [MessageCell] = []
    private var messages: [ChatMessage] = []
    private var look: SupporterLookChoice = .tryOn
    private var number: Int?
    private var laidOutWidth: CGFloat = 0
    private var contentHeight: CGFloat = 0
    private let images = AppContainer.shared.images
    private let animator = EmoteAnimator()

    private var headerHeight: CGFloat {
        ceil(header.font.lineHeight) + Self.padding
    }

    private static var padding: CGFloat {
        #if os(tvOS)
        24
        #else
        14
        #endif
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.backgroundColor = Theme.surface
        card.layer.cornerRadius = Self.padding + 6
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        addSubview(card)

        header.text = String(localized: "Chat preview")
        #if os(tvOS)
        header.font = .systemFont(ofSize: 24, weight: .semibold)
        #else
        header.font = .preferredFont(forTextStyle: .footnote)
        #endif
        header.textColor = Theme.secondaryText
        #if os(iOS)
        header.adjustsFontForContentSizeCategory = true
        #endif
        card.addSubview(header)

        messages = Self.sampleMessages(ownName: String(localized: "You"))
        for _ in messages {
            let cell = MessageCell(frame: .zero)
            cell.transform = CGAffineTransform(scaleX: 1, y: -1)
            cell.isUserInteractionEnabled = false
            cell.accessibilityElementsHidden = true
            card.addSubview(cell)
            cells.append(cell)
        }
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitUserInterfaceStyle.self, SupporterThemeTrait.self]) { (self: Self, _: UITraitCollection) in
            self.relayout()
        }
        Task { [weak self] in
            guard let user = await AuthService.shared.currentUser() else { return }
            self?.setOwnName(user.displayName)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Shows the given look on the viewer's own message.
    func show(_ look: SupporterLookChoice, number: Int?) {
        guard look != self.look || number != self.number else { return }
        self.look = look
        self.number = number
        relayout()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        card.frame = bounds
        if bounds.width != laidOutWidth {
            relayout()
        }
    }

    private func setOwnName(_ name: String) {
        messages = Self.sampleMessages(ownName: name)
        relayout()
    }

    private func relayout() {
        let width = bounds.width
        guard width > 0 else { return }
        laidOutWidth = width
        let inset = Self.padding
        header.frame = CGRect(x: inset, y: inset, width: width - inset * 2, height: ceil(header.font.lineHeight))
        let preview = MessageLayout.Preview(
            authorID: Self.ownID,
            look: SupporterDirectory.Look(badge: look.badgeColor.badge, color: look.badgeColor, nameStyle: look.nameStyle, number: number),
            font: look.chatFont
        )
        let layout = MessageLayout(
            width: width - inset,
            settings: SettingsStore.shared.current,
            catalog: EmoteCatalog(),
            badges: BadgeCatalog(),
            preview: preview
        )
        var y = inset + headerHeight
        for (cell, message) in zip(cells, messages) {
            let laidOut = layout.layout(message)
            cell.configure(with: laidOut, message: message, images: images, animator: animator)
            cell.frame = CGRect(x: inset / 2, y: y, width: laidOut.width, height: laidOut.height)
            y += laidOut.height
        }
        accessibilityLabel = ([header.text ?? ""] + messages.map { "\($0.author.displayName): \($0.plainText)" }).joined(separator: ". ")
        let height = ceil(y + inset * 0.6)
        if height != contentHeight {
            contentHeight = height
            invalidateIntrinsicContentSize()
        }
    }

    private static func sampleMessages(ownName: String) -> [ChatMessage] {
        let now = Date()
        let lines: [(ChatUser, String)] = [
            (ChatUser(id: "embr-preview-1", login: "pixelpilot", displayName: "PixelPilot", color: ChatColor(red: 30, green: 180, blue: 110)), String(localized: "that clutch was unreal")),
            (ChatUser(id: ownID, login: "you", displayName: ownName, color: ChatColor(red: 70, green: 140, blue: 255)), String(localized: "first time catching this live, what a stream")),
            (ChatUser(id: "embr-preview-2", login: "nightowl", displayName: "nightowl", color: ChatColor(red: 255, green: 120, blue: 60)), String(localized: "gg everyone")),
        ]
        return lines.enumerated().map { index, line in
            ChatMessage(
                id: "embr-preview-\(index)",
                channelID: "embr-preview",
                timestamp: now,
                author: line.0,
                fragments: [.text(line.1)]
            )
        }
    }
}
