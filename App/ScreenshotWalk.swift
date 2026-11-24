#if DEBUG
import UIKit
import MidgarKit

/// Walks the heaviest screens in one launch, giving each its own frame-watch line and drawing it into
/// `Library/Logs/<name>.png`, so the same walk measures a screen before and after a change. Reached with
/// `SHOT_ROUTE=walk` and `EMBR_DEMO=1`; every step runs the ordinary screenshot route for that screen.
@MainActor
enum ScreenshotWalk {
    private struct Step {
        let name: String
        let route: String
        let entry: TimeInterval
        let dwell: TimeInterval
        let scrolls: Bool

        var scrollAt: TimeInterval { entry + 2.2 }
        var reportAt: TimeInterval { entry + dwell }
    }

    private static let steps: [Step] = [
        Step(name: "Top", route: "top", entry: 2.0, dwell: 4.6, scrolls: true),
        Step(name: "Following", route: "following", entry: 7.4, dwell: 4.6, scrolls: true),
        Step(name: "Channel", route: "channel", entry: 12.8, dwell: 6.4, scrolls: true),
        Step(name: "Chats", route: "chats", entry: 20.0, dwell: 4.2, scrolls: true),
        Step(name: "Clips", route: "clips", entry: 25.0, dwell: 5.4, scrolls: false),
        Step(name: "Supporter", route: "supporter", entry: 31.2, dwell: 5.0, scrolls: true)
    ]

    static func start(on tabBar: RootTabBarController, deepLinks: DeepLinkRouter) {
        Task { @MainActor in
            if DemoWorld.isActive { await AuthService.shared.seedScreenshotAuth() }
            for step in steps { schedule(step, on: tabBar, deepLinks: deepLinks) }
        }
    }

    private static func schedule(_ step: Step, on tabBar: RootTabBarController, deepLinks: DeepLinkRouter) {
        after(step.entry) {
            MidgarFrameWatch.shared.stop()
            MidgarFrameWatch.shared.start()
            ScreenshotRouter.perform(step.route, on: tabBar, deepLinks: deepLinks)
        }
        if step.scrolls {
            after(step.scrollAt) { scrollPrimaryList(in: tabBar.view) }
            after(step.scrollAt + 0.35) { scrollPrimaryList(in: tabBar.view) }
        }
        after(step.reportAt) { report(step.name, on: tabBar) }
    }

    /// Ends the step's stretch under its name, then draws the window beside the log for comparison with the next run.
    private static func report(_ name: String, on tabBar: RootTabBarController) {
        MidgarFrameWatch.shared.report(name)
        guard let window = keyWindow(for: tabBar),
              let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appending(path: "Logs") else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let written = (try? image.pngData()?.write(to: logs.appending(path: "\(name).png"))) != nil
        MidgarLog.info("walk snapshot \(name): \(window.bounds.size), written \(written), \(image.size)", category: .app)
        MidgarFrameWatch.shared.disregardWhatJustRan()
    }

    /// The window on screen, which is the tab bar's unless a screen was presented over it full screen.
    private static func keyWindow(for tabBar: RootTabBarController) -> UIWindow? {
        if let window = tabBar.view.window { return window }
        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow) }
            .first
    }

    private static func after(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated(work) }
    }

    /// The biggest scroll view on the screen, so a list, the chat and a long page all take the same scroll.
    private static func scrollPrimaryList(in root: UIView) {
        var found: [(view: UIScrollView, area: CGFloat)] = []
        collectScrollViews(in: root, into: &found)
        guard let scroll = found.max(by: { $0.area < $1.area })?.view else { return }
        let limit = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        guard limit > 0 else { return }
        let target = min(limit, max(0, scroll.contentOffset.y) + scroll.bounds.height * 0.62)
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: target), animated: true)
    }

    private static func collectScrollViews(in view: UIView, into found: inout [(view: UIScrollView, area: CGFloat)]) {
        if let scroll = view as? UIScrollView, !scroll.isHidden, scroll.alpha > 0.01, scroll.window != nil {
            found.append((scroll, scroll.bounds.width * scroll.bounds.height))
        }
        for child in view.subviews { collectScrollViews(in: child, into: &found) }
    }
}
#endif
