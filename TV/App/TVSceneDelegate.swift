import UIKit
import Combine
import EmbrCore
import MidgarCore

final class TVSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var root: TVStudioRootViewController?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.tintColor = StudioPalette.emberLight
        window.traitOverrides[SupporterThemeTrait.self] = SupporterStore.shared.theme
        window.overrideUserInterfaceStyle = .dark
        window.backgroundColor = StudioPalette.background
        let root = TVStudioRootViewController()
        self.root = root
        window.rootViewController = root
        self.window = window
        window.makeKeyAndVisible()
        #if DEBUG
        Task { await TVScreenshotRoute.perform(on: root) }
        #endif
        MidgarLog.info("tv scene connected", category: .app)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        Task { await SupporterDirectory.shared.refreshIfStale() }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        SettingsStore.shared.flush()
    }
}
