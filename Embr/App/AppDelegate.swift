import UIKit
import EmbrCore

enum OrientationCoordinator {
    nonisolated(unsafe) static var mask: UIInterfaceOrientationMask = .portrait
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    private let didFirstRunKey = "didFirstRun"

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationCoordinator.mask
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        performFirstRunIfNeeded()
        _ = AppContainer.shared
        NetworkMonitor.shared.start()
        RemoteConfigService.shared.start()
        TipJarStore.shared.start()
        AppLogger.shared.info("app launched", category: .app)
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    private func performFirstRunIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didFirstRunKey) else { return }
        KeychainTokenStore.shared.clearSync()
        defaults.set(true, forKey: didFirstRunKey)
        AppLogger.shared.info("first run: wiped stale credentials", category: .app)
    }
}
