#if DEBUG
import UIKit
import EmbrCore
import MidgarKit

/// Drives the app straight to a screen for App Store and Duo screenshot capture. Every option is
/// read from a launch argument (`-screenshotRoute channel`) or, for tools that can only set the
/// environment, from `SHOT_ROUTE=channel`. DEBUG-only; never compiled into a Release build.
@MainActor
enum ScreenshotRouter {
    private static let completedOnboardingKey = "completedOnboarding"

    static func option(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-screenshot" + name), index + 1 < args.count {
            return args[index + 1]
        }
        return ProcessInfo.processInfo.environment["SHOT_" + name.uppercased()]
    }

    /// Returns whether a route was found. `onboarding` is found but left to the scene delegate,
    /// which presents the real first-run screen when the completed flag is clear.
    static func handle(_ tabBar: RootTabBarController, deepLinks: DeepLinkRouter) -> Bool {
        guard let route = option("Route") else { return false }
        UserDefaults.standard.set(route != "onboarding", forKey: completedOnboardingKey)
        ScreenshotHarness.isPosing = true
        applyAppearance()
        if DemoWorld.isActive { seedDemoState() }
        if option("Sidebar") == "shown" { tabBar.sidebar.isHidden = false }
        if let seconds = option("PopAfter").flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak tabBar] in
                tabBar?.selectedNavigationController?.popToRootViewController(animated: true)
            }
        }
        ScreenshotHarness.searchQuery = option("Query")
        ScreenshotHarness.hidesStatusBar = option("StatusBar") == "hidden"
        tabBar.setNeedsStatusBarAppearanceUpdate()
        ScreenshotHarness.skippedLogins = Set(option("Skip")?.lowercased().split(separator: ",").map(String.init) ?? [])
        if route == "onboarding" { return false }
        let wantsSession = option("Auth") == "1" || route == "following"
        Task { @MainActor in
            if wantsSession, DemoWorld.isActive {
                await AuthService.shared.seedScreenshotAuth()
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            perform(route, on: tabBar, deepLinks: deepLinks)
        }
        return true
    }

    private static func applyAppearance() {
        if let theme = option("Theme") {
            SettingsStore.shared.update { $0.theme = theme == "dark" ? .dark : (theme == "light" ? .light : .system) }
        }
    }

    /// Everything a demo capture shows besides the live-looking lists: the starred channels, the
    /// recently watched row and a clean slate for the settings a previous capture may have changed.
    private static func seedDemoState() {
        SettingsStore.shared.update { $0.chatOnly = false }
        UserDefaults.standard.removeObject(forKey: "channel.chatColumnWidth")
        let favoriteLogins = option("Favorites")?.split(separator: ",").map(String.init) ?? DemoWorld.favoriteLogins
        FavoritesStore.shared.seedForScreenshots(favoriteLogins.compactMap { login in
            DemoWorld.channel(login: login).map {
                FavoriteChannel(id: $0.id, login: $0.login, name: $0.name, addedAt: Date())
            }
        })
        WatchHistoryStore.shared.seedForScreenshots(DemoWorld.recentLogins.compactMap { login in
            DemoWorld.channel(login: login).map { WatchedChannel(id: $0.id, login: $0.login, name: $0.name) }
        })
    }

    private static func perform(_ route: String, on tabBar: RootTabBarController, deepLinks: DeepLinkRouter) {
        let channel = option("Channel")
        switch route {
        case "top": tabBar.select(.top)
        case "categories":
            tabBar.select(.top)
            after(0.5) {
                let top = (tabBar.selectedViewController as? UINavigationController)?.viewControllers.first as? TopViewController
                top?.showCategoriesForScreenshot()
            }
        case "game":
            tabBar.select(.top)
            let id = option("Game") ?? "9104"
            let name = DemoWorld.game(id: id)?.name ?? id
            let category = GameCategory(id: id, name: name, boxArtURLTemplate: DemoWorld.boxArtTemplate(gameID: id))
            tabBar.selectedNavigationController?.pushViewController(
                TopViewController(mode: .game(category), api: AppContainer.shared.api), animated: false)
        case "search": tabBar.select(.search)
        case "settings": tabBar.select(.settings)
        case "support":
            ScreenshotHarness.previewTips = true
            tabBar.select(.settings)
            after(0.6) {
                let settings = (tabBar.selectedViewController as? UINavigationController)?.viewControllers.first as? SettingsViewController
                settings?.showSupportForScreenshot()
            }
        case "favorites":
            tabBar.select(.favorites)
            if !DemoWorld.isActive {
                let logins = option("Favorites")?.split(separator: ",").map(String.init)
                Task { await seedLiveFavorites(logins ?? ScreenshotHarness.curatedFollowLogins) }
            }
        case "videos":
            guard let channel else { return }
            Task {
                guard let user = try? await AppContainer.shared.api.user(login: channel) else { return }
                let videos = ChannelVideosViewController(broadcasterID: user.id, channelName: user.displayName)
                tabBar.selectedNavigationController?.pushViewController(videos, animated: false)
                if let segment = option("Segment").flatMap(Int.init) {
                    after(0.4) { videos.selectSegmentForScreenshot(segment) }
                }
            }
        case "vod":
            guard let channel else { return }
            tabBar.selectedNavigationController?.pushViewController(
                VideoViewController(source: .vod(id: "vod-\(channel)-\(option("Index") ?? "0")")), animated: false)
        case "open":
            if let target = option("URL"), let url = URL(string: target) {
                Task { await deepLinks.handle(url, from: tabBar) }
            }
        case "following":
            if DemoWorld.isActive {
                tabBar.select(.following)
            } else {
                ScreenshotHarness.seededFollow = true
                Task { await AuthService.shared.seedScreenshotAuth() }
            }
        case "alertsprompt":
            tabBar.select(.top)
            after(0.6) { LiveAlertsPrompt.offerAfterSignIn(from: tabBar) }
        case "followingsignin":
            tabBar.select(.top)
            after(0.6) {
                tabBar.selectedNavigationController?.pushViewController(FollowingViewController(), animated: false)
            }
        case "moreapps":
            tabBar.select(.settings)
            after(0.8) {
                guard let nav = tabBar.selectedViewController as? UINavigationController, let top = nav.topViewController else { return }
                Midgar.present(from: top)
            }
        case "profile":
            openChannel(channel, deepLinks: deepLinks, tabBar: tabBar)
            after(3.0) {
                let login = option("Profile") ?? "kitsunetea"
                let host = tabBar.selectedNavigationController?.topViewController
                host?.present(ProfileSheetViewController(login: login, navigator: tabBar.selectedNavigationController), animated: false)
            }
        case "channel", "channelaudio", "channelchat", "channelfull", "channelfullchat":
            let poses: [String: ScreenshotHarness.ChannelPose] = [
                "channelaudio": .audio, "channelchat": .chat,
                "channelfull": .fullscreen, "channelfullchat": .fullscreenChat
            ]
            ScreenshotHarness.channelPose = poses[route] ?? .normal
            openChannel(channel, deepLinks: deepLinks, tabBar: tabBar)
        default: break
        }
    }

    private static func openChannel(_ login: String?, deepLinks: DeepLinkRouter, tabBar: RootTabBarController) {
        guard let login, let url = URL(string: "embr://channel/\(login)") else { return }
        Task { await deepLinks.handle(url, from: tabBar) }
    }

    private static func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated(work) }
    }

    /// Turns the window sideways for a capture. An iPad app only accepts this when its capture
    /// copy is marked full-screen (see docs/screenshots); the phone accepts it once a video page
    /// that allows landscape is showing, hence the delay.
    static func requestLandscape(from tabBar: RootTabBarController, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak tabBar] in
            guard let scene = tabBar?.view.window?.windowScene else { return }
            OrientationCoordinator.phoneMask = [.portrait, .landscapeLeft, .landscapeRight]
            OrientationCoordinator.rotate(scene, to: .landscapeRight) { error in
                AppLogger.shared.warn("screenshot rotation refused: \(error.localizedDescription)", category: .app)
            }
        }
    }

    /// Stars the given channels in memory only, resolving their ids live.
    private static func seedLiveFavorites(_ logins: [String]) async {
        var seeded: [FavoriteChannel] = []
        for login in logins {
            guard let user = try? await AppContainer.shared.api.user(login: login) else { continue }
            seeded.append(FavoriteChannel(id: user.id, login: user.login, name: user.displayName, addedAt: Date()))
        }
        FavoritesStore.shared.seedForScreenshots(seeded)
    }
}
#endif
