import UIKit
import Combine
import EmbrCore
import MidgarCore

/// Founding Member on iPhone and iPad. Before the purchase it is a fitting room: every look can be tried on, shown
/// on this screen and in a chat preview drawn by the real chat, and the purchase keeps exactly what was tried on. For a
/// member the same controls change the app at once, with their founding number and the state of their badge.
final class SupporterViewController: UIViewController {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let flame = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let preview = SupporterChatPreview()
    private let controls = SupporterLookControls()
    private let badgeLabel = UILabel()
    private let badgeRetry = UIButton(configuration: .plain())
    private let buyBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let buyButton = UIButton(configuration: .borderedProminent())
    private let buyNote = UILabel()
    private let restoreButton = UIButton(configuration: .plain())
    private var cancellables = Set<AnyCancellable>()
    private var purchasing = false
    private var draft = SupporterLookChoice.tryOn

    init() {
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
        navigationItem.largeTitleDisplayMode = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = SupporterCopy.name(number: nil)
        view.backgroundColor = Theme.background
        draft.icon = SupporterStore.currentIcon
        buildLayout()
        buildBuyBar()
        controls.onChange = { [weak self] choice in self?.choose(choice) }
        SupporterStore.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.render() }
            .store(in: &cancellables)
        SupporterStore.shared.loadProduct()
        #if DEBUG
        poseForScreenshots()
        #endif
        render()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let barHeight = buyBar.isHidden ? 0 : buyBar.bounds.height - view.safeAreaInsets.bottom
        if scrollView.contentInset.bottom != barHeight {
            scrollView.contentInset.bottom = barHeight
            scrollView.verticalScrollIndicatorInsets.bottom = barHeight
        }
    }

    private func buildLayout() {
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 20, leading: 20, bottom: 32, trailing: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        flame.contentMode = .scaleAspectFit
        flame.heightAnchor.constraint(equalToConstant: 112).isActive = true
        flame.accessibilityIgnoresInvertColors = true

        titleLabel.font = .preferredFont(forTextStyle: .title1).bold
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header

        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.textColor = Theme.secondaryText
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0

        badgeLabel.font = .preferredFont(forTextStyle: .footnote)
        badgeLabel.adjustsFontForContentSizeCategory = true
        badgeLabel.textColor = Theme.secondaryText
        badgeLabel.numberOfLines = 0
        badgeLabel.textAlignment = .center
        badgeRetry.configuration?.title = String(localized: "Try Again")
        badgeRetry.addAction(UIAction { _ in SupporterStore.shared.retryBadge() }, for: .primaryActionTriggered)

        restoreButton.configuration?.title = String(localized: "Restore Purchase")
        restoreButton.addAction(UIAction { [weak self] _ in self?.restore() }, for: .primaryActionTriggered)

        [flame, titleLabel, bodyLabel, preview, badgeLabel, badgeRetry, controls, restoreButton].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(10, after: flame)
        stack.setCustomSpacing(8, after: titleLabel)
        stack.setCustomSpacing(22, after: bodyLabel)
        stack.setCustomSpacing(6, after: preview)
        stack.setCustomSpacing(28, after: badgeRetry)
        stack.setCustomSpacing(28, after: controls)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 600),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor).withPriority(.defaultHigh),
        ])
    }

    /// The purchase stays in reach while someone scrolls through the looks.
    private func buildBuyBar() {
        buyBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buyBar)

        buyButton.configuration?.cornerStyle = .large
        buyButton.configuration?.buttonSize = .large
        buyButton.addAction(UIAction { [weak self] _ in self?.buy() }, for: .primaryActionTriggered)

        buyNote.font = .preferredFont(forTextStyle: .caption1)
        buyNote.adjustsFontForContentSizeCategory = true
        buyNote.textColor = Theme.secondaryText
        buyNote.textAlignment = .center
        buyNote.numberOfLines = 0

        let content = UIStackView(arrangedSubviews: [buyButton, buyNote])
        content.axis = .vertical
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        buyBar.contentView.addSubview(content)
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        buyBar.contentView.addSubview(separator)

        NSLayoutConstraint.activate([
            buyBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            buyBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            buyBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            separator.topAnchor.constraint(equalTo: buyBar.topAnchor),
            separator.leadingAnchor.constraint(equalTo: buyBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: buyBar.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / max(1, traitCollection.displayScale)),
            content.topAnchor.constraint(equalTo: buyBar.contentView.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            content.centerXAnchor.constraint(equalTo: buyBar.contentView.centerXAnchor),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
            content.widthAnchor.constraint(equalTo: buyBar.contentView.widthAnchor, constant: -40).withPriority(.defaultHigh),
        ])
    }

    /// The looks on screen: the member's own, or what is being tried on.
    private var shown: SupporterLookChoice {
        SupporterStore.shared.isSupporter ? SupporterStore.shared.choice : draft
    }

    private func choose(_ choice: SupporterLookChoice) {
        let store = SupporterStore.shared
        guard store.isSupporter else {
            draft = choice
            render()
            return
        }
        let current = store.choice
        if choice.theme != current.theme { store.setTheme(choice.theme) }
        if choice.accent != current.accent { store.setAccent(choice.accent) }
        if choice.chatFont != current.chatFont { store.setChatFont(choice.chatFont) }
        if choice.badgeColor != current.badgeColor || choice.nameStyle != current.nameStyle {
            store.setBadgeStyle(color: choice.badgeColor, nameStyle: choice.nameStyle)
        }
        if choice.icon != current.icon {
            SupporterStore.setIcon(choice.icon)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.render() }
        }
        render()
    }

    private func render() {
        let store = SupporterStore.shared
        let supporter = store.isSupporter
        let look = shown

        if supporter {
            traitOverrides.remove(SupporterThemeTrait.self)
            view.tintColor = nil
        } else {
            traitOverrides[SupporterThemeTrait.self] = look.theme
            view.tintColor = look.accent.color
        }

        flame.image = look.badgeColor.flameImage
        if supporter {
            titleLabel.text = SupporterCopy.name(number: store.number)
            bodyLabel.text = SupporterCopy.ownerBody
        } else {
            titleLabel.text = SupporterCopy.invitation
            bodyLabel.text = SupporterCopy.invitationBody
        }
        preview.show(look, number: supporter ? store.number : nil)
        controls.show(look)

        badgeLabel.text = badgeText(store)
        badgeLabel.isHidden = badgeLabel.text == nil
        badgeRetry.isHidden = store.badge != .failed

        buyBar.isHidden = supporter
        restoreButton.isHidden = supporter
        if let price = store.product?.displayPrice {
            buyButton.configuration?.title = String(localized: "Unlock the Looks · \(price)")
            buyButton.isEnabled = !purchasing
        } else if store.productUnavailable {
            buyButton.configuration?.title = String(localized: "Try Again")
            buyButton.isEnabled = true
        } else {
            buyButton.configuration?.title = String(localized: "Loading Price…")
            buyButton.isEnabled = false
        }
        buyButton.configuration?.showsActivityIndicator = purchasing
        buyButton.tintColor = look.accent.color
        buyButton.configuration?.baseForegroundColor = look.accent.prefersDarkText ? .black : .white
        buyNote.text = buyNoteText(store)
        view.setNeedsLayout()
    }

    private func buyNoteText(_ store: SupporterStore) -> String {
        if store.productUnavailable && store.product == nil {
            return String(localized: "Purchases are not available right now.")
        }
        return SupporterCopy.purchaseNote(count: store.supporterCount)
    }

    private func badgeText(_ store: SupporterStore) -> String? {
        guard store.isSupporter else { return nil }
        switch store.badge {
        case .needsSignIn: return String(localized: "Log in with Twitch in Settings to show your badge in chat.")
        case .shown(let login): return String(localized: "Your badge shows beside \(login) in chat.")
        case .failed: return String(localized: "Your badge couldn't be turned on yet.")
        case .claiming: return String(localized: "Turning on your badge…")
        case .none: return nil
        }
    }

    private func buy() {
        guard !purchasing else { return }
        guard SupporterStore.shared.product != nil else {
            SupporterStore.shared.loadProduct()
            return
        }
        purchasing = true
        render()
        let tried = draft
        Task { [weak self] in
            let outcome = await SupporterStore.shared.purchase(in: self?.view.window?.windowScene, tryingOn: tried)
            guard let self else { return }
            self.purchasing = false
            switch outcome {
            case .purchased:
                self.render()
                self.celebrate()
            case .pending:
                self.render()
                self.alert(String(localized: "Waiting for Approval"), String(localized: "The purchase finishes once it's approved."))
            case .cancelled:
                self.render()
            case .failed(let message):
                self.render()
                Haptics.notify(.error)
                self.alert(String(localized: "Purchase Failed"), message)
            }
        }
    }

    /// Brings the flame into view, then lets the sparks fly from where it now is.
    private func celebrate() {
        Haptics.notify(.success)
        UIAccessibility.post(notification: .announcement, argument: SupporterCopy.bought(number: SupporterStore.shared.number))
        let top = CGPoint(x: 0, y: -scrollView.adjustedContentInset.top)
        let play = { [weak self] in
            guard let self else { return }
            SupporterCelebration.play(from: self.flame, color: SupporterStore.shared.choice.badgeColor.color)
        }
        guard !UIAccessibility.isReduceMotionEnabled else {
            scrollView.setContentOffset(top, animated: false)
            play()
            return
        }
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState], animations: {
            self.scrollView.contentOffset = top
        }, completion: { _ in play() })
    }

    #if DEBUG
    /// Tries a look on and scrolls for a screenshot: `-screenshotLook theme,flame,nameStyle,font,accent` and
    /// `-screenshotScroll <points>`.
    private func poseForScreenshots() {
        if let look = ScreenshotRouter.option("Look")?.split(separator: ",").map(String.init), look.count == 5 {
            draft.theme = SupporterTheme(rawValue: look[0]) ?? draft.theme
            draft.badgeColor = SupporterAccent(rawValue: look[1]) ?? draft.badgeColor
            draft.nameStyle = SupporterAPI.NameStyle(rawValue: look[2]) ?? draft.nameStyle
            draft.chatFont = SupporterChatFont(rawValue: look[3]) ?? draft.chatFont
            draft.accent = SupporterAccent(rawValue: look[4]) ?? draft.accent
        }
        if let offset = ScreenshotRouter.option("Scroll").flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let scrollView = self?.scrollView else { return }
                scrollView.setContentOffset(CGPoint(x: 0, y: offset - scrollView.adjustedContentInset.top), animated: false)
            }
        }
    }
    #endif

    private func restore() {
        Task { [weak self] in
            if !(await SupporterStore.shared.restore()) {
                self?.alert(String(localized: "Nothing to Restore"), SupporterCopy.nothingToRestore)
            }
        }
    }

    private func alert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }
}

private extension UIFont {
    var bold: UIFont {
        fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: 0) } ?? self
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
