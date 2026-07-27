import StoreKit
import UIKit

/// Asks for an App Store rating once the user has actually watched a meaningful amount of stream
/// through Embr, and at most once per app version.
///
/// Rating count is both an App Store ranking input and the strongest conversion signal on a
/// product page, and Embr shipped with no way to ask for one. The gate is accumulated watch time
/// rather than a tap: opening a channel proves nothing, staying in it does. Time is banked when
/// the channel screen is left, so a stream left running in the background never inflates it.
@MainActor
enum ReviewPrompt {
    private static let watchSecondsBeforeAsking: TimeInterval = 15 * 60
    private static let minimumCreditedVisit: TimeInterval = 30
    private static let secondsKey = "embr.review.watchedSeconds"
    private static let versionKey = "embr.review.promptedVersion"

    /// Banks a completed viewing stretch and asks once the total clears the threshold.
    static func recordWatchTime(_ seconds: TimeInterval, in scene: UIWindowScene?) {
        guard seconds >= minimumCreditedVisit else { return }
        let defaults = UserDefaults.standard
        let total = defaults.double(forKey: secondsKey) + seconds
        defaults.set(total, forKey: secondsKey)

        guard total >= watchSecondsBeforeAsking else { return }
        guard defaults.string(forKey: versionKey) != currentVersion, let scene else { return }
        defaults.set(currentVersion, forKey: versionKey)
        AppLogger.shared.info(
            "review prompt requested after \(Int(total))s watched", category: .app)
        AppStore.requestReview(in: scene)
    }

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}
