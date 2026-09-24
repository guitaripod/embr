import UIKit
import Combine
import EmbrCore
import MidgarKit

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

        #if DEBUG
        if handleScreenshotRoute(tabBar) {
            AppLogger.shared.info("scene connected (screenshot route)", category: .app)
            return
        }
        #endif

        let pending = connectionOptions.urlContexts
        if !presentOnboardingIfNeeded(over: tabBar, then: pending) {
            handle(pending)
        }
        AppLogger.shared.info("scene connected", category: .app)
    }

    #if DEBUG
    /// Drives the app straight to a screen for App Store screenshot capture, e.g.
    /// `-screenshotRoute channel -screenshotChannel shroud`. DEBUG-only; never ships.
    private func handleScreenshotRoute(_ tabBar: RootTabBarController) -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screenshotRoute"), i + 1 < args.count else { return false }
        UserDefaults.standard.set(true, forKey: completedOnboardingKey)
        ScreenshotHarness.isPosing = true
        let route = args[i + 1]
        func arg(_ name: String) -> String? {
            args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }
        let channel = arg("-screenshotChannel")
        if let theme = arg("-screenshotTheme") {
            SettingsStore.shared.update { $0.theme = theme == "dark" ? .dark : (theme == "light" ? .light : .system) }
        }
        ScreenshotHarness.searchQuery = arg("-screenshotQuery")
        ScreenshotHarness.skippedLogins = Set(arg("-screenshotSkip")?.lowercased().split(separator: ",").map(String.init) ?? [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak tabBar] in
            guard let self, let tabBar else { return }
            switch route {
            case "top": tabBar.select(.top)
            case "categories":
                tabBar.select(.top)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let top = (tabBar.selectedViewController as? UINavigationController)?.viewControllers.first as? TopViewController
                    top?.showCategoriesForScreenshot()
                }
            case "search": tabBar.select(.search)
            case "settings": tabBar.select(.settings)
            case "support":
                ScreenshotHarness.previewTips = true
                tabBar.select(.settings)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    let settings = (tabBar.selectedViewController as? UINavigationController)?.viewControllers.first as? SettingsViewController
                    settings?.showSupportForScreenshot()
                }
            case "favorites":
                tabBar.select(.favorites)
                let logins = arg("-screenshotFavorites")?.split(separator: ",").map(String.init)
                Task { await Self.seedScreenshotFavorites(logins ?? ScreenshotHarness.curatedFollowLogins) }
            case "open":
                if let target = arg("-screenshotURL"), let url = URL(string: target) {
                    Task { await self.router.handle(url, from: tabBar) }
                }
            case "following":
                ScreenshotHarness.seededFollow = true
                Task { await AuthService.shared.seedScreenshotAuth() }
            case "moreapps":
                tabBar.select(.settings)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    guard let nav = tabBar.selectedViewController as? UINavigationController, let top = nav.topViewController else { return }
                    Midgar.present(from: top, config: MidgarConfig(accent: Theme.accent, title: "More Apps"))
                }
            case "channel", "channelaudio", "channelchat":
                ScreenshotHarness.channelPose = route == "channelaudio" ? .audio : (route == "channelchat" ? .chat : .normal)
                if let channel, let url = URL(string: "embr://channel/\(channel)") {
                    Task { await self.router.handle(url, from: tabBar) }
                }
            default: break
            }
        }
        return true
    }

    /// Stars the given channels in memory only, resolving their ids live.
    @MainActor
    private static func seedScreenshotFavorites(_ logins: [String]) async {
        var seeded: [FavoriteChannel] = []
        for login in logins {
            guard let user = try? await AppContainer.shared.api.user(login: login) else { continue }
            seeded.append(FavoriteChannel(id: user.id, login: user.login, name: user.displayName, addedAt: Date()))
        }
        FavoritesStore.shared.seedForScreenshots(seeded)
    }
    #endif

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
