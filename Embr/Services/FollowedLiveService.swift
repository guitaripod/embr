import UIKit
import UserNotifications
import EmbrCore

/// Polls the signed-in user's followed live channels on launch/foreground, badges
/// the Following tab with the live count, and fires a local notification for
/// channels that have newly gone live since the last check.
@MainActor
final class FollowedLiveService {
    static let shared = FollowedLiveService()

    private let auth: AuthControlling
    private let api: TwitchAPIProviding
    private weak var tabBar: RootTabBarController?
    private var lastLiveIDs: Set<String> = []
    private var seeded = false
    private var refreshing = false
    private var requestedAuthorization = false
    private var generation = 0
    private var lastRefreshAt: Date?
    private let minRefreshInterval: TimeInterval = 60

    init(auth: AuthControlling = AuthService.shared, api: TwitchAPIProviding = TwitchAPIClient.shared) {
        self.auth = auth
        self.api = api
    }

    func start(tabBar: RootTabBarController) {
        self.tabBar = tabBar
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshNow),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
        refreshForced()
    }

    @objc func refreshNow() {
        Task { await refresh(forced: false) }
    }

    func refreshForced() {
        Task { await refresh(forced: true) }
    }

    func reset() {
        generation &+= 1
        lastLiveIDs = []
        seeded = false
        lastRefreshAt = nil
        tabBar?.setFollowingBadge(0)
    }

    private func refresh(forced: Bool) async {
        guard !refreshing else { return }
        if !forced, let last = lastRefreshAt, Date().timeIntervalSince(last) < minRefreshInterval { return }
        refreshing = true
        defer { refreshing = false }

        guard let user = await auth.currentUser() else {
            reset()
            return
        }
        let token = generation
        guard let page = try? await api.followedStreams(userID: user.id, after: nil, first: 100) else { return }
        guard token == generation else { return }
        let live = page.items
        let liveIDs = Set(live.map(\.userID))
        tabBar?.setFollowingBadge(live.count)

        if seeded {
            let newlyLive = live.filter { !lastLiveIDs.contains($0.userID) }
            if !newlyLive.isEmpty { await notify(newlyLive) }
        } else {
            seeded = true
            requestAuthorizationIfNeeded()
        }
        guard token == generation else { return }
        lastLiveIDs = liveIDs
        lastRefreshAt = Date()
    }

    private func requestAuthorizationIfNeeded() {
        guard !requestedAuthorization else { return }
        requestedAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ streams: [LiveStream]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        for stream in streams.prefix(5) {
            let content = UNMutableNotificationContent()
            content.title = "\(stream.userName) is live"
            let detail = stream.title.isEmpty ? stream.gameName : stream.title
            content.body = detail.isEmpty ? "Streaming now" : detail
            content.sound = .default
            let request = UNNotificationRequest(identifier: "live-\(stream.userID)", content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}
