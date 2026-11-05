import UIKit
import Combine
import EmbrCore

/// The channels the signed-in viewer follows: who is live, then everyone else by avatar.
final class TVFollowingViewController: TVShelfViewController {
    private var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        TVLiveDirectory.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.render() }
            .store(in: &cancellables)
        AppContainer.shared.auth.statePublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    override func load() async {
        if TVLiveDirectory.shared.lastRefresh == nil { stateView.showLoading() }
        await TVLiveDirectory.shared.refresh()
        let directory = TVLiveDirectory.shared
        await directory.loadAvatars(for: directory.followed.prefix(60).map(\.id) + WatchHistoryStore.shared.recent.prefix(20).map(\.id))
        render()
    }

    private func render() {
        let directory = TVLiveDirectory.shared
        guard directory.isSignedIn else {
            apply([])
            stateView.show(
                symbol: "person.crop.circle.badge.plus",
                title: String(localized: "See who you follow"),
                message: String(localized: "Sign in with Twitch to see your followed channels live, and their chat as you."),
                buttonTitle: String(localized: "Sign In with Twitch")
            ) { [weak self] in
                guard let self else { return }
                TVRouter.signIn(from: self)
            }
            return
        }
        let live = directory.followedLive
        let liveIDs = Set(live.map(\.userID))
        let offline = directory.followed
            .filter { !liveIDs.contains($0.id) }
            .prefix(60)
            .map { channel in
                TVShelfItem.channel(TVChannelSummary(
                    id: channel.id, login: channel.broadcasterLogin, name: channel.broadcasterName,
                    avatarURL: directory.avatar(for: channel.id), isLive: false
                ))
            }
        let recent = WatchHistoryStore.shared.recent.prefix(20).map { entry in
            TVShelfItem.channel(TVChannelSummary(
                id: entry.id, login: entry.login, name: entry.name,
                avatarURL: directory.avatar(for: entry.id), isLive: liveIDs.contains(entry.id)
            ))
        }
        apply([
            TVShelf(id: "live", title: String(localized: "Live Now"), style: .featured, items: live.map(TVShelfItem.stream)),
            TVShelf(id: "recent", title: String(localized: "Recently Watched"), style: .channels, items: Array(recent)),
            TVShelf(id: "offline", title: String(localized: "Offline"), style: .channels, items: Array(offline)),
        ])
        if live.isEmpty && offline.isEmpty {
            stateView.show(
                symbol: "moon.zzz",
                title: String(localized: "Nobody you follow is live"),
                message: String(localized: "Follow channels on Twitch and they show up here.")
            )
        } else if live.isEmpty {
            stateView.hide()
        }
    }
}
