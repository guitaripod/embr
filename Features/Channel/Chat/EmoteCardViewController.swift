import UIKit
import SDWebImage
import EmbrCore

/// A small sheet for an emote tapped in chat: the emote large and moving, its name and where it comes from, with a
/// button to put it in the message being written.
@MainActor
final class EmoteCardViewController: UIViewController {
    private let emote: Emote
    private let images: ImageLoading
    private let onInsert: ((Emote) -> Void)?
    private let preview = SDAnimatedImageView()
    private var loadTask: Task<Void, Never>?

    init(emote: Emote, images: ImageLoading, onInsert: ((Emote) -> Void)?) {
        self.emote = emote
        self.images = images
        self.onInsert = onInsert
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            let fitted = UIFontMetrics(forTextStyle: .body).scaledValue(for: 300)
            sheet.detents = [.custom(identifier: .init("emote")) { context in min(fitted, context.maximumDetentValue) }, .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.surface

        preview.contentMode = .scaleAspectFit
        preview.autoPlayAnimatedImage = SettingsStore.shared.current.animateEmotes
        preview.isAccessibilityElement = true
        preview.accessibilityLabel = emote.name
        preview.accessibilityTraits = .image

        let name = UILabel()
        name.text = emote.name
        name.font = .preferredFont(forTextStyle: .title2).withWeight(.bold)
        name.adjustsFontForContentSizeCategory = true
        name.textColor = Theme.primaryText
        name.textAlignment = .center

        let detail = UILabel()
        detail.text = Self.detail(for: emote)
        detail.font = .preferredFont(forTextStyle: .subheadline)
        detail.adjustsFontForContentSizeCategory = true
        detail.textColor = Theme.secondaryText
        detail.textAlignment = .center

        let actions = UIStackView()
        actions.axis = .horizontal
        actions.spacing = ChatMetrics.rowSpacing
        actions.distribution = .fillEqually
        actions.addArrangedSubview(button(String(localized: "Copy Name"), symbol: "doc.on.doc", prominent: onInsert == nil) { [weak self] in
            guard let self else { return }
            UIPasteboard.general.string = self.emote.name
            Haptics.notify(.success)
            self.dismiss(animated: true)
        })
        if onInsert != nil {
            actions.addArrangedSubview(button(String(localized: "Insert"), symbol: "plus.bubble", prominent: true) { [weak self] in
                guard let self else { return }
                Haptics.selection()
                let emote = self.emote
                let insert = self.onInsert
                self.dismiss(animated: true) { insert?(emote) }
            })
        }

        let stack = UIStackView(arrangedSubviews: [preview, name, detail, actions])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 6
        stack.setCustomSpacing(14, after: preview)
        stack.setCustomSpacing(20, after: detail)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            preview.heightAnchor.constraint(equalToConstant: 96),
            actions.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])

        loadTask = Task { [weak self] in
            guard let self else { return }
            let image = await self.images.emoteImage(for: self.emote, scale: .x4)
            guard !Task.isCancelled else { return }
            self.preview.image = image
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        loadTask?.cancel()
    }

    private static func detail(for emote: Emote) -> String {
        var parts = [emote.provider.displayName]
        if emote.isAnimated { parts.append(String(localized: "Animated")) }
        if emote.isZeroWidth { parts.append(String(localized: "Overlay")) }
        return parts.joined(separator: " · ")
    }

    private func button(_ title: String, symbol: String, prominent: Bool, action: @escaping () -> Void) -> UIButton {
        var config = prominent ? UIButton.Configuration.filled() : UIButton.Configuration.gray()
        config.title = title
        config.image = UIImage(systemName: symbol)
        config.imagePadding = 6
        config.cornerStyle = .capsule
        if prominent {
            config.baseBackgroundColor = Theme.accent
            config.baseForegroundColor = Theme.onAccent
        }
        return UIButton(configuration: config, primaryAction: UIAction { _ in action() })
    }
}
