import Foundation
import UserNotifications
import SDWebImage
import EmbrCore

/// Erases everything Embr keeps on this device: the GRDB store, the in-memory stores that
/// mirror it, every UserDefaults key, pending and delivered notifications, and the image and
/// URL caches. The log files stay, since they hold no account data and support relies on them.
struct AppDataEraser: LocalDataErasing {
    func eraseAll() async {
        await DatabaseManager.shared.eraseAllData()
        await resetInMemoryStores()
        clearDefaults()
        clearNotifications()
        await clearCaches()
        AppLogger.shared.info("erased all on-device data", category: .persistence)
    }

    @MainActor
    private func resetInMemoryStores() {
        SettingsStore.shared.reset()
        WatchHistoryStore.shared.clear()
        FavoritesStore.shared.reset()
        FollowedLiveService.shared.reset()
    }

    /// Removing the whole persistent domain also drops the onboarding flag, which is what
    /// routes the next launch back into first-run onboarding.
    private func clearDefaults() {
        guard let domain = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }

    private func clearNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    private func clearCaches() async {
        URLCache.shared.removeAllCachedResponses()
        SDImageCache.shared.clearMemory()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            SDImageCache.shared.clearDisk { continuation.resume() }
        }
    }
}
