import UIKit
import EmbrCore

/// The phone browses in portrait and turns to landscape only while a video is on screen. iPad
/// windows resize freely, so every orientation is always allowed there.
@MainActor
enum OrientationCoordinator {
    static var phoneMask: UIInterfaceOrientationMask = .portrait

    static var mask: UIInterfaceOrientationMask {
        isPhone ? phoneMask : .all
    }

    static var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
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

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }
        KeyCommands.build(into: builder)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        KeyCommands.canPerform(action) ?? super.canPerformAction(action, withSender: sender)
    }

    override func validate(_ command: UICommand) {
        super.validate(command)
        KeyCommands.validate(command)
    }

    private func performFirstRunIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didFirstRunKey) else { return }
        KeychainTokenStore.shared.clearSync()
        defaults.set(true, forKey: didFirstRunKey)
        AppLogger.shared.info("first run: wiped stale credentials", category: .app)
    }
}
