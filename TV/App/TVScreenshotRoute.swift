#if DEBUG
import UIKit
import EmbrCore

/// Drives the Apple TV app straight to a screen for App Store screenshots, from `-tvRoute <name>`, in the invented
/// world of `-embrDemo`. DEBUG only.
@MainActor
enum TVScreenshotRoute {
    static var route: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-tvRoute"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// The starred channels and the signed-in viewer of the invented world.
    static func seedDemo() {
        guard DemoWorld.isActive else { return }
        FavoritesStore.shared.seedForScreenshots(DemoWorld.favoriteLogins.compactMap { login in
            DemoWorld.channel(login: login).map { FavoriteChannel(id: $0.id, login: $0.login, name: $0.name, addedAt: Date()) }
        })
        WatchHistoryStore.shared.seedForScreenshots(DemoWorld.recentLogins.compactMap { login in
            DemoWorld.channel(login: login).map { WatchedChannel(id: $0.id, login: $0.login, name: $0.name) }
        })
        SettingsStore.shared.update { $0.livePreviews = false }
    }

    static func perform(on root: TVRootViewController) async {
        guard let route else { return }
        if DemoWorld.isActive, route != "signedout" {
            await AuthService.shared.seedScreenshotAuth()
        }
        try? await Task.sleep(for: .seconds(1))
        let select: (String) -> Void = { id in
            if let tab = root.tabs.first(where: { $0.identifier == id }) { root.selectedTab = tab }
        }
        switch route {
        case "following": select(Settings.StartTab.following.rawValue)
        case "favorites": select(Settings.StartTab.favorites.rawValue)
        case "browse", "signedout": select(Settings.StartTab.top.rawValue)
        case "player":
            guard let stream = await liveStreams().first else { return }
            TVPlaybackCoordinator.play(.live(stream), from: root)
        case "multiview":
            TVMultiviewViewController.present(starting: Array(await liveStreams().prefix(4)), from: root)
        case "channel":
            select(Settings.StartTab.favorites.rawValue)
            try? await Task.sleep(for: .seconds(0.5))
            if let login = DemoWorld.favoriteLogins.first { TVRouter.openChannel(login: login, from: root) }
        case "supporter", "supporterowned":
            SupporterStore.shared.seedForScreenshots(supporter: route == "supporterowned")
            select("settings")
            try? await Task.sleep(for: .seconds(0.5))
            (root.selectedViewController as? UINavigationController)?.pushViewController(TVSupporterViewController(), animated: false)
        case "signin":
            TVRouter.signIn(from: root)
        default:
            break
        }
    }

    private static func liveStreams() async -> [LiveStream] {
        (try? await AppContainer.shared.api.topStreams(after: nil, first: 8).items) ?? []
    }
}
#endif
