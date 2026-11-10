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
        ScreenshotHarness.moderates = option("Moderator") == "1"
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
        let highlights = option("Highlights") == "1"
        SettingsStore.shared.update {
            $0.chatOnly = false
            $0.highlightMentions = true
            $0.highlightWords = highlights ? ["clip", "song"] : nil
            $0.highlightUsers = highlights ? ["tobias_ward"] : nil
            $0.moderatorTools = DemoWorld.showsModeration
        }
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
        case "search":
            tabBar.select(.search)
            if let cycles = option("KeyboardCycles").flatMap(Int.init) {
                cycleKeyboard(in: tabBar, times: cycles, startingAfter: option("KeyboardAt").flatMap(Double.init) ?? 6)
            }
        case "settings":
            tabBar.select(.settings)
            if let page = option("SettingsPage") {
                after(0.6) {
                    let settings = tabBar.settingsNavigationController.viewControllers.first as? SettingsViewController
                    settings?.showPageForScreenshot(page, query: ScreenshotHarness.searchQuery)
                }
            }
        case "support":
            ScreenshotHarness.previewTips = true
            tabBar.select(.settings)
            after(0.6) {
                let settings = tabBar.settingsNavigationController.viewControllers.first as? SettingsViewController
                settings?.showSupportForScreenshot()
            }
        case "supporter", "supporterowned":
            SupporterStore.shared.seedForScreenshots(supporter: route == "supporterowned")
            tabBar.select(.settings)
            after(0.6) {
                tabBar.settingsNavigationController.pushViewController(SupporterViewController(), animated: false)
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
        case "studio":
            StudioLauncher.openSample(from: tabBar)
            if let moment = option("StudioMoment") {
                after(2.5) {
                    let navigation = tabBar.presentedViewController as? UINavigationController
                    (navigation?.viewControllers.first as? StudioViewController)?.showMomentForScreenshot(moment)
                }
            }
        case "studiosettings":
            tabBar.select(.settings)
            after(0.6) {
                tabBar.settingsNavigationController.pushViewController(StudioSettingsViewController(), animated: false)
            }
        case "studiopro":
            ScreenshotHarness.previewStudioPrices = true
            tabBar.present(UINavigationController(rootViewController: StudioProViewController()), animated: false)
        case "clips":
            guard let channel else { return }
            Task {
                guard let user = try? await AppContainer.shared.api.user(login: channel),
                      let page = try? await AppContainer.shared.api.clips(broadcasterID: user.id, after: nil, first: 20),
                      !page.items.isEmpty else { return }
                let start = option("Index").flatMap(Int.init) ?? 0
                let pager = ClipPager(api: AppContainer.shared.api, broadcasterID: user.id, cursor: page.cursor, hasMore: page.cursor != nil)
                tabBar.present(ClipFeedViewController(clips: page.items, startIndex: start, pager: pager), animated: false)
            }
        case "vod":
            guard let channel else { return }
            let info = DemoWorld.channel(login: channel)
            let index = option("Index") ?? "0"
            let vod = VideoOnDemand(
                id: "vod-\(channel)-\(index)",
                userID: info?.id ?? channel,
                userLogin: channel,
                userName: info?.name ?? channel,
                title: info?.title ?? String(localized: "Past Broadcast"),
                createdAt: Date(),
                publishedAt: Date(),
                thumbnailURLTemplate: "https://\(DemoWorld.host)/vod/\(channel)\(index)/%{width}x%{height}",
                viewCount: 0,
                durationSeconds: 7200,
                type: "archive"
            )
            tabBar.selectedNavigationController?.pushViewController(
                VODViewController(vod: vod), animated: false)
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
                guard let top = tabBar.settingsNavigationController.topViewController else { return }
                Midgar.present(from: top, config: EmbrMidgar.shared.portalConfig)
            }
        case "profile":
            openChannel(channel, deepLinks: deepLinks, tabBar: tabBar)
            after(3.0) {
                let login = option("Profile") ?? "kitsunetea"
                let host = tabBar.selectedNavigationController?.topViewController
                host?.present(ProfileSheetViewController(login: login, navigator: tabBar.selectedNavigationController), animated: false)
            }
        case "usercard":
            ScreenshotHarness.channelPose = .chat
            openChannel(channel, deepLinks: deepLinks, tabBar: tabBar)
            after(5.0) {
                let host = tabBar.selectedNavigationController?.topViewController
                host.flatMap(chatController(in:))?.presentUserCardForScreenshot(login: option("Profile"))
            }
        case "chats":
            let logins = option("Chats")?.split(separator: ",").map(String.init) ?? ["lumenfox", "pixelpilgrim", "northerncrane"]
            if DemoWorld.isActive {
                ChatsModel.shared.seedForScreenshots(logins.compactMap { login in
                    DemoWorld.channel(login: login).map { ChatsModel.Entry(id: $0.id, login: $0.login, name: $0.name) }
                })
            } else {
                Task { await seedLiveChats(count: Int(option("ChatCount") ?? "") ?? 3) }
            }
            tabBar.select(.chats)
            if let sheet = option("Sheet") {
                after(8.0) {
                    (tabBar.selectedNavigationController?.viewControllers.first as? ChatsViewController)?.presentForScreenshot(sheet)
                }
            }
        case "modqueue":
            ScreenshotHarness.channelPose = .chat
            openChannel(channel, deepLinks: deepLinks, tabBar: tabBar)
            after(5.0) {
                let host = tabBar.selectedNavigationController?.topViewController
                host.flatMap(chatController(in:))?.presentModerationQueueForScreenshot()
            }
        case "highlights":
            tabBar.select(.settings)
            after(0.8) {
                tabBar.settingsNavigationController.pushViewController(HighlightsViewController(), animated: false)
            }
        case "channel", "channelaudio", "channelchat", "channelfull", "channelfullchat":
            let poses: [String: ScreenshotHarness.ChannelPose] = [
                "channelaudio": .audio, "channelchat": .chat,
                "channelfull": .fullscreen, "channelfullchat": .fullscreenChat
            ]
            ScreenshotHarness.channelPose = poses[route] ?? .normal
            openChannel(channel, deepLinks: deepLinks, tabBar: tabBar)
            if let cycles = option("KeyboardCycles").flatMap(Int.init) {
                cycleKeyboard(in: tabBar, times: cycles, startingAfter: option("KeyboardAt").flatMap(Double.init) ?? 6)
            }
            if let seconds = option("TurnBack").flatMap(Double.init) {
                let turn = option("TurnAt").flatMap(Double.init) ?? 4
                requestLandscape(from: tabBar, after: turn)
                requestPortrait(from: tabBar, after: turn + seconds)
                after(turn + seconds + 2) { snapshotWindow(of: tabBar, named: "turnback") }
            }
            if let seconds = option("SnapshotAt").flatMap(Double.init) {
                after(seconds) { snapshotWindow(of: tabBar, named: option("SnapshotName") ?? "channel") }
            }
        default: break
        }
    }

    /// Opens and closes the chat keyboard over and over on a channel page, for a screen recording of the keyboard's
    /// arrival: `-screenshotKeyboardCycles <n>`, starting `-screenshotKeyboardAt <seconds>` after launch.
    private static func cycleKeyboard(in tabBar: RootTabBarController, times: Int, startingAfter delay: Double) {
        for cycle in 0..<times {
            let start = delay + Double(cycle) * 3.5
            after(start) {
                guard let top = tabBar.presentedViewController ?? tabBar.selectedViewController else { return }
                KeyboardProbe.shared.watch(cycle: cycle, scene: tabBar.view.window?.windowScene)
                if let chat = chatController(in: top) {
                    chat.focusComposer()
                } else {
                    _ = firstTextInput(in: top.view)?.becomeFirstResponder()
                }
            }
            after(start + 2) { tabBar.view.window?.endEditing(true) }
        }
    }

    /// The first text field or text view under a view, for keyboard captures on screens without chat.
    private static func firstTextInput(in view: UIView) -> UIView? {
        if view is UITextField || view is UITextView { return view }
        for child in view.subviews {
            if let found = firstTextInput(in: child) { return found }
        }
        return nil
    }

    /// The chat inside a screen, however deep the screen nests it.
    private static func chatController(in controller: UIViewController) -> ChatViewController? {
        if let chat = controller as? ChatViewController { return chat }
        for child in controller.children {
            if let chat = chatController(in: child) { return chat }
        }
        return nil
    }

    /// Opens a channel by login; `top` opens the busiest live Just Chatting channel, or the busiest of any.
    private static func openChannel(_ login: String?, deepLinks: DeepLinkRouter, tabBar: RootTabBarController) {
        guard let login else { return }
        Task {
            var target = login
            if login == "top" {
                let streams = (try? await AppContainer.shared.api.topStreams(after: nil, first: 40).items) ?? []
                guard let pick = streams.first(where: { $0.gameName == "Just Chatting" }) ?? streams.first else { return }
                target = pick.userLogin
            }
            guard let url = URL(string: "embr://channel/\(target)") else { return }
            await deepLinks.handle(url, from: tabBar)
        }
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
                MidgarLog.notice("screenshot rotation refused: \(error.localizedDescription)", category: .app)
            }
        }
    }

    /// Draws the window into Library/Logs/<name>.png, where `devicectl ... copy from` reaches it on a phone that no
    /// screenshot tool can.
    private static func snapshotWindow(of tabBar: RootTabBarController, named name: String) {
        guard let window = tabBar.view.window,
              let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appending(path: "Logs") else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try? image.pngData()?.write(to: logs.appending(path: "\(name).png"))
        MidgarLog.info("snapshot \(name): \(window.bounds.size)", category: .app)
    }

    /// Turns the window back upright, for checking what a trip to landscape leaves behind.
    static func requestPortrait(from tabBar: RootTabBarController, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak tabBar] in
            guard let scene = tabBar?.view.window?.windowScene else { return }
            OrientationCoordinator.rotate(scene, to: .portrait) { error in
                MidgarLog.notice("screenshot rotation refused: \(error.localizedDescription)", category: .app)
            }
        }
    }

    /// Opens the chats of the busiest live channels in memory only, to try several real chats on one connection.
    private static func seedLiveChats(count: Int) async {
        let streams = (try? await AppContainer.shared.api.topStreams(after: nil, first: count).items) ?? []
        ChatsModel.shared.seedForScreenshots(streams.map { ChatsModel.Entry(id: $0.userID, login: $0.userLogin, name: $0.userName) })
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
/// Logs, frame by frame for a moment after the keyboard is asked for, where every keyboard-hosting view sits on
/// screen, so a keyboard that flashes in the wrong place shows up in `embr.log` on a real device.
@MainActor
final class KeyboardProbe: NSObject {
    static let shared = KeyboardProbe()
    private var link: CADisplayLink?
    private var started = CFAbsoluteTimeGetCurrent()
    private var cycle = 0
    private weak var scene: UIWindowScene?

    func watch(cycle: Int, scene: UIWindowScene?) {
        link?.invalidate()
        self.cycle = cycle
        self.scene = scene
        started = CFAbsoluteTimeGetCurrent()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() {
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        guard elapsed < 0.9, let scene else {
            link?.invalidate()
            link = nil
            return
        }
        for window in scene.windows {
            record(window, in: window, depth: 0, elapsed: elapsed)
        }
    }

    private func record(_ view: UIView, in window: UIWindow, depth: Int, elapsed: Double) {
        let name = String(describing: type(of: view))
        let interesting = ["Keyboard", "InputSet", "InputView", "Remote", "Prediction", "Assistant"].contains { name.contains($0) }
        if interesting, !view.isHidden {
            let shown = view.layer.presentation() ?? view.layer
            let target = window.layer.presentation() ?? window.layer
            let frame = shown.convert(shown.bounds, to: target)
            MidgarLog.notice(String(format: "kbprobe c%d t%.3f %@ in %@ y=%.0f h=%.0f w=%.0f a=%.2f", cycle, elapsed, name, String(describing: type(of: window)), frame.minY, frame.height, frame.width, shown.opacity), category: .app)
        }
        guard depth < 7 else { return }
        for child in view.subviews { record(child, in: window, depth: depth + 1, elapsed: elapsed) }
    }
}
#endif
