import UIKit
import Combine
import EmbrCore
import MidgarCore

final class TVSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var root: TVRootViewController?
    private var cancellables = Set<AnyCancellable>()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.tintColor = Theme.accent
        window.traitOverrides[SupporterThemeTrait.self] = SupporterStore.shared.theme
        window.overrideUserInterfaceStyle = Self.style(for: SettingsStore.shared.current.theme)
        Self.paint(window)
        window.registerForTraitChanges([UITraitUserInterfaceStyle.self, SupporterThemeTrait.self]) { (window: UIWindow, _: UITraitCollection) in
            Self.paint(window)
        }
        let root = TVRootViewController()
        self.root = root
        window.rootViewController = root
        self.window = window
        window.makeKeyAndVisible()

        SettingsStore.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak window] settings in
                window?.overrideUserInterfaceStyle = Self.style(for: settings.theme)
            }
            .store(in: &cancellables)

        let pending = connectionOptions.urlContexts
        Task { [weak self] in
            await FavoritesStore.shared.load()
            let signedIn = await AppContainer.shared.auth.currentUser() != nil
            root.selectStartTab(signedIn: signedIn)
            self?.handle(pending)
            #if DEBUG
            await TVScreenshotRoute.perform(on: root)
            #endif
        }
        MidgarLog.info("tv scene connected", category: .app)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        handle(URLContexts)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        Task {
            await TVLiveDirectory.shared.refreshIfStale()
            await SupporterDirectory.shared.refreshIfStale()
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        SettingsStore.shared.flush()
        TVLivePreview.shared.stop()
    }

    private func handle(_ contexts: Set<UIOpenURLContext>) {
        guard let root else { return }
        for context in contexts {
            guard let link = EmbrLink(url: context.url) else {
                MidgarLog.notice("tv: unhandled url \(context.url.absoluteString)", category: .app)
                continue
            }
            MidgarLog.info("tv: opening \(context.url.absoluteString)", category: .app)
            TVRouter.handle(link, from: root)
        }
    }

    /// Fills the window with the page color for its current appearance and theme. A window resolves a dynamic
    /// background once and keeps it, so this runs again whenever the Apple TV or Embr's Appearance setting switches
    /// between light and dark, or a supporter changes theme.
    private static func paint(_ window: UIWindow) {
        window.backgroundColor = Theme.background.resolvedColor(with: window.traitCollection)
    }

    private static func style(for theme: Settings.ThemePreference) -> UIUserInterfaceStyle {
        switch theme {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}
