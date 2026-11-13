import UIKit
import EmbrCore
import MidgarCore

@main
final class TVAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        EmbrMidgar.configureLogging()
        #if DEBUG
        DemoWorld.resetLaunchState()
        #endif
        _ = AppContainer.shared
        EmbrMidgar.shared.start()
        NetworkMonitor.shared.start()
        RemoteConfigService.shared.start()
        SupporterStore.shared.start()
        StudioProStore.shared.start()
        MidgarLog.info("tv app launched", category: .app)
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = TVSceneDelegate.self
        return configuration
    }
}
