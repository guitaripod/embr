#if DEBUG
import UIKit
import EmbrCore

/// Drives the Apple TV app straight to a Studio screen for App Store screenshots and UI checks, from `-tvRoute <name>`:
/// the sample stream, optionally at one of its moments (`-tvMoment raid|gift|hype|poll|prediction|adsoon|adrun|offline|actions`)
/// and posed for the App Store with `-tvStoreCapture`.
/// DEBUG only.
@MainActor
enum TVScreenshotRoute {
    static var route: String? { argument("-tvRoute") }
    static var moment: String? { argument("-tvMoment") }
    /// `-tvStoreCapture` poses the sample as a real live channel for App Store captures: no sample markers, and the half
    /// hour before the moment in the alert feed.
    static var storeCapture: Bool { ProcessInfo.processInfo.arguments.contains("-tvStoreCapture") }

    private static func argument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func perform(on root: TVStudioRootViewController) async {
        guard let route else { return }
        try? await Task.sleep(for: .seconds(1.5))
        switch route {
        case "sample":
            root.openSample()
            if storeCapture {
                try? await Task.sleep(for: .seconds(1))
                root.seedHistoryForScreenshot()
            }
            guard let moment else { return }
            try? await Task.sleep(for: .seconds(2))
            root.showMomentForScreenshot(moment)
        case "welcome", "signedout":
            break
        case "pro":
            root.present(TVStudioProViewController(), animated: false)
        case "settings":
            root.openSample()
            try? await Task.sleep(for: .seconds(1))
            let navigation = UINavigationController(rootViewController: TVSettingsViewController(coordinator: root))
            navigation.modalPresentationStyle = .fullScreen
            root.present(navigation, animated: false)
        default:
            break
        }
    }
}
#endif
