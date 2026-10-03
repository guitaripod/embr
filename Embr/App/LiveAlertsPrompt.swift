import UIKit
import UserNotifications
import EmbrCore

/// Explains, in one line, what live alerts are for and only then asks iOS for permission. Offered
/// once, right after a viewer signs in, because alerts cover the channels a signed-in viewer follows.
@MainActor
enum LiveAlertsPrompt {
    private static let offeredKey = "embr.liveAlerts.offered"
    private static let defaults = UserDefaults.standard

    static func offerAfterSignIn(from presenter: UIViewController) {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let status: LiveAlertsPromptPolicy.SystemStatus = settings.authorizationStatus == .notDetermined ? .notDetermined : .answered
            guard LiveAlertsPromptPolicy.shouldOffer(
                isSignedIn: true,
                systemStatus: status,
                alreadyOffered: defaults.bool(forKey: offeredKey)
            ) else { return }
            present(from: presenter)
        }
    }

    private static func present(from presenter: UIViewController) {
        let host = topmost(from: presenter)
        guard host.viewIfLoaded?.window != nil, !host.isBeingPresented, !host.isBeingDismissed else {
            AppLogger.shared.info("live alerts pre-prompt skipped: no stable screen to present on", category: .ui)
            return
        }
        defaults.set(true, forKey: offeredKey)
        let alert = UIAlertController(
            title: String(localized: "Get Live Alerts?"),
            message: String(localized: "Get a notification when a channel you follow goes live."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "Not Now"), style: .cancel) { _ in
            AppLogger.shared.info("live alerts pre-prompt declined", category: .ui)
        })
        alert.addAction(UIAlertAction(title: String(localized: "Turn On Alerts"), style: .default) { _ in
            requestSystemAuthorization()
        })
        alert.preferredAction = alert.actions.last
        host.present(alert, animated: true)
        AppLogger.shared.info("live alerts pre-prompt shown", category: .ui)
    }

    private static func requestSystemAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                AppLogger.shared.warn("live alerts authorization failed: \(error)", category: .app)
            } else {
                AppLogger.shared.info("live alerts authorization granted=\(granted)", category: .app)
            }
        }
    }

    private static func topmost(from controller: UIViewController) -> UIViewController {
        var top = controller
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
