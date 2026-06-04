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
        logo.addSymbolEffect(.pulse, options: .repeating)

        let title = UILabel()
        title.text = "Embr"
        title.font = .systemFont(ofSize: 40, weight: .bold)
        title.textColor = Theme.primaryText
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "A fast, native Twitch client. Browse live channels, watch streams, and chat — without the bloat."
        subtitle.font = .systemFont(ofSize: 17, weight: .regular)
        subtitle.textColor = Theme.secondaryText
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        configure(connectButton, title: "Connect Twitch Account", filled: true)
        connectButton.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)

        configure(guestButton, title: "Continue as Guest", filled: false)
        guestButton.addTarget(self, action: #selector(guestTapped), for: .touchUpInside)

        activity.hidesWhenStopped = true
        activity.color = Theme.accent

        let header = UIStackView(arrangedSubviews: [logo, title, subtitle])
        header.axis = .vertical
        header.alignment = .center
        header.spacing = 16

        let buttons = UIStackView(arrangedSubviews: [connectButton, guestButton, activity])
        buttons.axis = .vertical
        buttons.alignment = .fill
        buttons.spacing = 12

        let container = UIStackView(arrangedSubviews: [header, buttons])
        container.axis = .vertical
        container.spacing = 48
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            container.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            container.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            container.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            connectButton.heightAnchor.constraint(equalToConstant: 52),
            guestButton.heightAnchor.constraint(equalToConstant: 52)
        ])
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
        setBusy(true)
        Task {
            do {
                let anchor: ASPresentationAnchor = view.window ?? ASPresentationAnchor()
                let user = try await auth.login(presentationAnchor: anchor)
                AppLogger.shared.info("onboarding login succeeded for \(user.login)", category: .auth)
                finish()
            } catch {
                AppLogger.shared.warn("onboarding login failed: \(error)", category: .auth)
                setBusy(false)
                presentLoginError()
            }
        }
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
            title: "Sign In Failed",
            message: "Could not connect your Twitch account. You can continue as a guest and sign in later.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
