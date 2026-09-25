import EmbrCore
import StoreKit
import UIKit

/// Asks for an App Store rating once Embr has actually delivered its value — a live stream
/// watched continuously for `continuousWatchSecondsForSuccess` — and paces every later ask
/// against `ReviewPromptPolicy`.
@MainActor
enum ReviewPrompt {
    static let continuousWatchSecondsForSuccess: TimeInterval = 3 * 60

    private static let askDelay: TimeInterval = 1.5

    private static let defaults = UserDefaults.standard
    private static let successCountKey = "embr.review.successCount"
    private static let askDatesKey = "embr.review.askDates"
    private static let successCountAtLastAskKey = "embr.review.successCountAtLastAsk"
    private static let migratedLegacyStateKey = "embr.review.migratedLegacyState"
    private static let legacyPromptedVersionKey = "embr.review.promptedVersion"

    /// Banks a success and, if `ReviewPromptPolicy` now calls for it, requests a review shortly
    /// after so the success UI lands first.
    static func recordStreamWatched(in scene: UIWindowScene?) {
        migrateLegacyStateIfNeeded()

        let successCount = defaults.integer(forKey: successCountKey) + 1
        defaults.set(successCount, forKey: successCountKey)
        AppLogger.shared.info("review success #\(successCount): watched a stream", category: .app)

        guard ReviewPromptPolicy.shouldAsk(
            successCount: successCount,
            askDates: storedAskDates(),
            successCountAtLastAsk: defaults.integer(forKey: successCountAtLastAskKey),
            now: Date()
        ) else {
            AppLogger.shared.info("review prompt skipped: not due yet", category: .app)
            return
        }
        guard let scene else {
            AppLogger.shared.info("review prompt skipped: no window scene", category: .app)
            return
        }
        let work = DispatchWorkItem { requestReviewIfStillSafe(successCount: successCount, scene: scene) }
        DispatchQueue.main.asyncAfter(deadline: .now() + askDelay, execute: work)
    }

    private static func requestReviewIfStillSafe(successCount: Int, scene: UIWindowScene) {
        guard scene.activationState == .foregroundActive else {
            AppLogger.shared.info("review prompt skipped: scene not foreground-active", category: .app)
            return
        }
        guard let keyWindow = scene.keyWindow, keyWindow.rootViewController?.presentedViewController == nil else {
            AppLogger.shared.info("review prompt skipped: other UI on screen", category: .app)
            return
        }
        let askDates = storedAskDates() + [Date()]
        persist(askDates: askDates)
        defaults.set(successCount, forKey: successCountAtLastAskKey)
        AppLogger.shared.info("review prompt requested (ask #\(askDates.count))", category: .app)
        AppStore.requestReview(in: scene)
    }

    private static func storedAskDates() -> [Date] {
        (defaults.array(forKey: askDatesKey) as? [Double] ?? []).map(Date.init(timeIntervalSince1970:))
    }

    private static func persist(askDates: [Date]) {
        defaults.set(askDates.map(\.timeIntervalSince1970), forKey: askDatesKey)
    }

    /// The old policy banked accumulated watch time across visits and prompted at most once per
    /// app version; it left no ask date behind, only a flag that it had fired. Any such flag
    /// counts as one prior ask toward the rolling-year cap, dated at migration time since the
    /// real date was never recorded.
    private static func migrateLegacyStateIfNeeded() {
        guard !defaults.bool(forKey: migratedLegacyStateKey) else { return }
        defaults.set(true, forKey: migratedLegacyStateKey)
        guard defaults.string(forKey: legacyPromptedVersionKey) != nil else { return }
        persist(askDates: [Date()])
        defaults.set(0, forKey: successCountAtLastAskKey)
        AppLogger.shared.info("review prompt: migrated a prior ask from the retired watch-time mechanism", category: .app)
    }
}
