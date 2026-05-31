import UIKit
import EmbrCore

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private let completedOnboardingKey = "completedOnboarding"
    private let router = DeepLinkRouter()
    private var root: RootTabBarController?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        applyAppearance()

        let window = UIWindow(windowScene: windowScene)
        window.tintColor = Theme.accent
        window.backgroundColor = Theme.background

        let tabBar = RootTabBarController()
        self.root = tabBar
        window.rootViewController = tabBar
        self.window = window
        window.makeKeyAndVisible()

        presentOnboardingIfNeeded(over: tabBar)
        handle(connectionOptions.urlContexts)
        AppLogger.shared.info("scene connected", category: .app)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handle(URLContexts)
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

    private func presentOnboardingIfNeeded(over presenter: UIViewController) {
        guard !UserDefaults.standard.bool(forKey: completedOnboardingKey) else { return }
        let onboarding = OnboardingViewController { [weak self] in
            UserDefaults.standard.set(true, forKey: self?.completedOnboardingKey ?? "completedOnboarding")
            presenter.dismiss(animated: true)
        }
        onboarding.modalPresentationStyle = .fullScreen
        presenter.present(onboarding, animated: false)
    }

    private func applyAppearance() {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        tabBarAppearance.backgroundColor = Theme.surface
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithDefaultBackground()
        navBarAppearance.backgroundColor = Theme.surface
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
    }
}
