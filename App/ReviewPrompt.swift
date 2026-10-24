import MidgarCommerce
import MidgarCore
import StoreKit
import UIKit

/// Asks for an App Store rating once Embr has actually delivered its value, a live stream watched continuously for
/// `continuousWatchSecondsForSuccess`. `MidgarReviewPolicy` decides whether the ask is due; this type only reports
/// the success and, when the policy says yes, shows Apple's prompt if nothing else is on screen.
@MainActor
enum ReviewPrompt {
    static let continuousWatchSecondsForSuccess: TimeInterval = 3 * 60

    private static let askDelay: TimeInterval = 1.5

    static let policy: MidgarReviewPolicy = {
        let storage = MidgarReviewFileStorage(appID: EmbrMidgar.appID)
        LegacyReviewState.migrate(from: .standard, into: storage)
        return MidgarReviewPolicy(storage: storage)
    }()

    /// Counts one session. Call it once per launch.
    static func beginSession() {
        policy.beginSession()
    }

    /// Banks a success and, if the policy now calls for it, requests a review shortly after so the success UI
    /// lands first.
    static func recordStreamWatched(in scene: UIWindowScene?) {
        let due = policy.noteSuccess()
        MidgarLog.info("review success: watched a stream, due=\(due)", category: .app)
        guard due else { return }
        guard let scene else {
            MidgarLog.info("review prompt skipped: no window scene", category: .app)
            return
        }
        let work = DispatchWorkItem { requestReviewIfStillSafe(scene: scene) }
        DispatchQueue.main.asyncAfter(deadline: .now() + askDelay, execute: work)
    }

    private static func requestReviewIfStillSafe(scene: UIWindowScene) {
        guard scene.activationState == .foregroundActive else {
            MidgarLog.info("review prompt skipped: scene not foreground-active", category: .app)
            return
        }
        guard let keyWindow = scene.keyWindow, keyWindow.rootViewController?.presentedViewController == nil else {
            MidgarLog.info("review prompt skipped: other UI on screen", category: .app)
            return
        }
        policy.notePrompted()
        MidgarLog.info("review prompt requested", category: .app)
        AppStore.requestReview(in: scene)
    }
}

/// The ask history Embr kept before MidgarReviewPolicy: a list of ask dates, and before that a flag with the app
/// version that had asked. A person who was asked recently must not be asked again the day the policy changes, so
/// the newest ask becomes the policy's last prompt the first time it runs.
enum LegacyReviewState {
    static let askDatesKey = "embr.review.askDates"
    static let legacyPromptedVersionKey = "embr.review.promptedVersion"
    static let migratedKey = "embr.review.migratedToMidgar"

    static func migrate(from defaults: UserDefaults, into storage: any MidgarReviewStorage, now: Date = Date()) {
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        guard let lastAsk = lastAsk(in: defaults, now: now) else { return }
        var state = storage.load()
        guard state.lastPrompt == nil else { return }
        state.lastPrompt = lastAsk
        state.lastPromptedVersion = defaults.string(forKey: legacyPromptedVersionKey)
        storage.save(state)
    }

    /// The newest recorded ask, or `now` when only the old per-version flag survives, since its date was never kept.
    private static func lastAsk(in defaults: UserDefaults, now: Date) -> Date? {
        let dates = (defaults.array(forKey: askDatesKey) as? [Double] ?? []).map(Date.init(timeIntervalSince1970:))
        if let newest = dates.max() { return newest }
        return defaults.string(forKey: legacyPromptedVersionKey) == nil ? nil : now
    }
}
