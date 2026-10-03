import UIKit
import AuthenticationServices
import EmbrCore

@MainActor
final class OnboardingViewController: UIViewController {
    private let auth: AuthService
    private let onComplete: () -> Void

    private let connectButton = UIButton(type: .system)
    private let guestButton = UIButton(type: .system)
    private let activity = UIActivityIndicatorView(style: .medium)

    init(auth: AuthService = .shared, onComplete: @escaping () -> Void) {
        self.auth = auth
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        buildLayout()
    }

    private func buildLayout() {
        let logo = UIImageView(image: UIImage(systemName: "flame.fill"))
        logo.tintColor = Theme.accent
        logo.contentMode = .scaleAspectFit
        logo.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 64, weight: .semibold)
        if !Motion.reduced { logo.addSymbolEffect(.pulse, options: .repeating) }

        let title = UILabel()
        title.text = "Embr"
        title.font = .systemFont(ofSize: 40, weight: .bold)
        title.textColor = Theme.primaryText
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = String(localized: "A fast, native Twitch client. Browse live channels, watch streams, and chat — without the bloat.")
        subtitle.font = .systemFont(ofSize: 17, weight: .regular)
        subtitle.textColor = Theme.secondaryText
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        configure(connectButton, title: String(localized: "Connect Twitch Account"), filled: true)
        connectButton.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)

        configure(guestButton, title: String(localized: "Continue as Guest"), filled: false)
        guestButton.addTarget(self, action: #selector(guestTapped), for: .touchUpInside)

        activity.hidesWhenStopped = true
        activity.color = Theme.accent

        let header = UIStackView(arrangedSubviews: [logo, title, subtitle])
        header.axis = .vertical
        header.alignment = .center
        header.spacing = 16

        let buttons = UIStackView(arrangedSubviews: [connectButton, guestButton, makeFavoritesHint(), activity, makeLegalNotice()])
        buttons.axis = .vertical
        buttons.alignment = .fill
        buttons.spacing = 12
        buttons.setCustomSpacing(18, after: activity)

        let container = UIStackView(arrangedSubviews: [header, buttons])
        container.axis = .vertical
        container.spacing = 48
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        let fullWidth = container.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -64)
        fullWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 460),
            fullWidth,
            container.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            container.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            connectButton.heightAnchor.constraint(equalToConstant: 52),
            guestButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    private func makeFavoritesHint() -> UIView {
        let label = UILabel()
        label.text = String(localized: "No account needed: tap the star on any channel to keep it in Favorites.")
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = Theme.secondaryText
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }

    private func makeLegalNotice() -> UIView {
        let notice = UILabel()
        notice.text = String(localized: "Embr shows live Twitch chat — content created by other users that we don't control. There is zero tolerance for objectionable content or abusive behaviour: you can filter, report, and block from any message, and reports are reviewed and acted on.")
        notice.font = .systemFont(ofSize: 12, weight: .regular)
        notice.textColor = Theme.secondaryText
        notice.textAlignment = .center
        notice.numberOfLines = 0

        let caption = UILabel()
        caption.text = String(localized: "By continuing, you agree to our")
        caption.font = .systemFont(ofSize: 12, weight: .regular)
        caption.textColor = Theme.secondaryText
        caption.textAlignment = .center

        let terms = makeLinkButton(title: String(localized: "Terms of Use")) { [weak self] in
            self?.presentLegal(title: LegalText.termsTitle, body: LegalText.terms)
        }
        let and = UILabel()
        and.text = String(localized: "and")
        and.font = .systemFont(ofSize: 12, weight: .regular)
        and.textColor = Theme.secondaryText
        let privacy = makeLinkButton(title: String(localized: "Privacy Policy")) { [weak self] in
            self?.presentLegal(title: LegalText.privacyTitle, body: LegalText.privacy)
        }

        let links = UIStackView(arrangedSubviews: [terms, and, privacy])
        links.axis = .horizontal
        links.alignment = .center
        links.spacing = 5

        let agreement = UIStackView(arrangedSubviews: [caption, links])
        agreement.axis = .vertical
        agreement.alignment = .center
        agreement.spacing = 2

        let stack = UIStackView(arrangedSubviews: [notice, agreement])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        return stack
    }

    private func makeLinkButton(title: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = .zero
        var attributed = AttributedString(title)
        attributed.font = .systemFont(ofSize: 12, weight: .semibold)
        configuration.attributedTitle = attributed
        configuration.baseForegroundColor = Theme.accent
        let button = UIButton(configuration: configuration)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func presentLegal(title: String, body: String) {
        let legal = LegalViewController(title: title, body: body)
        let nav = UINavigationController(rootViewController: legal)
        legal.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak nav] _ in nav?.dismiss(animated: true) }
        )
        present(nav, animated: true)
    }

    private func configure(_ button: UIButton, title: String, filled: Bool) {
        var configuration = filled ? UIButton.Configuration.filled() : UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseBackgroundColor = filled ? Theme.accent : .clear
        configuration.baseForegroundColor = filled ? .white : Theme.accent
        configuration.cornerStyle = .large
        button.configuration = configuration
    }

    @objc private func connectTapped() {
        guard let anchor = presentationAnchor() else {
            AppLogger.shared.warn("onboarding login: no window anchor available", category: .auth)
            return
        }
        setBusy(true)
        Task {
            do {
                let user = try await auth.login(presentationAnchor: anchor)
                AppLogger.shared.info("onboarding login succeeded for \(user.login)", category: .auth)
                finish()
            } catch APIError.cancelled {
                AppLogger.shared.info("onboarding login cancelled by user", category: .auth)
                setBusy(false)
            } catch {
                AppLogger.shared.warn("onboarding login failed: \(error)", category: .auth)
                setBusy(false)
                presentLoginError()
            }
        }
    }

    private func presentationAnchor() -> ASPresentationAnchor? {
        if let window = view.window { return window }
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
    }

    @objc private func guestTapped() {
        AppLogger.shared.info("onboarding: continuing as guest", category: .app)
        finish()
    }

    private func finish() {
        onComplete()
    }

    private func setBusy(_ busy: Bool) {
        connectButton.isEnabled = !busy
        guestButton.isEnabled = !busy
        if busy { activity.startAnimating() } else { activity.stopAnimating() }
    }

    private func presentLoginError() {
        let alert = UIAlertController(
            title: String(localized: "Sign In Failed"),
            message: String(localized: "Could not connect your Twitch account. You can continue as a guest and sign in later."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }
}
