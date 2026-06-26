import UIKit
import Combine
import EmbrCore

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private let completedOnboardingKey = "completedOnboarding"
    private let router = DeepLinkRouter()
    private var root: RootTabBarController?
    private var cancellables = Set<AnyCancellable>()

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.tintColor = Theme.accent
        window.backgroundColor = Theme.background
        window.overrideUserInterfaceStyle = Self.interfaceStyle(for: SettingsStore.shared.current.theme)

        let tabBar = RootTabBarController()
        self.root = tabBar
        window.rootViewController = tabBar
        self.window = window
        window.makeKeyAndVisible()

        observeThemeChanges(window)

        let pending = connectionOptions.urlContexts
        if !presentOnboardingIfNeeded(over: tabBar, then: pending) {
            handle(pending)
        }
        AppLogger.shared.info("scene connected", category: .app)
    }

    private func observeThemeChanges(_ window: UIWindow) {
        SettingsStore.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak window] settings in
                window?.overrideUserInterfaceStyle = SceneDelegate.interfaceStyle(for: settings.theme)
            }
            .store(in: &cancellables)
    }

    private static func interfaceStyle(for theme: Settings.ThemePreference) -> UIUserInterfaceStyle {
        switch theme {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handle(URLContexts)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        SettingsStore.shared.flush()
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return }
        route(url)
    }

    private func handle(_ contexts: Set<UIOpenURLContext>) {
        for context in contexts {
            route(context.url)
        }
    }

    private func route(_ url: URL) {
        guard let root else { return }
        Task { await router.handle(url, from: root) }
    }

    @discardableResult
    private func presentOnboardingIfNeeded(over presenter: UIViewController, then pending: Set<UIOpenURLContext>) -> Bool {
        guard !UserDefaults.standard.bool(forKey: completedOnboardingKey) else { return false }
        let onboarding = OnboardingViewController { [weak self, weak presenter] in
            UserDefaults.standard.set(true, forKey: self?.completedOnboardingKey ?? "completedOnboarding")
            presenter?.dismiss(animated: true) {
                self?.handle(pending)
            }
        }
        onboarding.modalPresentationStyle = .fullScreen
        presenter.present(onboarding, animated: false)
        return true
    }

}
