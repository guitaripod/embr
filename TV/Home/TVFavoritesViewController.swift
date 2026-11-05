import UIKit
import Combine
import EmbrCore

/// The channels starred in Embr, on this Apple TV or on the iPhone through iCloud: live first, then the rest.
final class TVFavoritesViewController: TVShelfViewController {
    private var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        TVLiveDirectory.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.render() }
            .store(in: &cancellables)
        FavoritesStore.shared.changes
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    override func load() async {
        if TVLiveDirectory.shared.lastRefresh == nil { stateView.showLoading() }
        await TVLiveDirectory.shared.refresh()
        await TVLiveDirectory.shared.loadAvatars(for: FavoritesStore.shared.channels.map(\.id))
        render()
    }

    private func render() {
        let directory = TVLiveDirectory.shared
        let favorites = FavoritesStore.shared.channels
        let live = directory.favoritesLive.filter { stream in favorites.contains { $0.id == stream.userID } }
        let liveIDs = Set(live.map(\.userID))
        let offline = favorites.filter { !liveIDs.contains($0.id) }.map { channel in
            TVShelfItem.channel(TVChannelSummary(
                id: channel.id, login: channel.login, name: channel.name,
                avatarURL: directory.avatar(for: channel.id), isLive: false
            ))
        }
        apply([
            TVShelf(id: "live", title: String(localized: "Live Now"), style: .featured, items: live.map(TVShelfItem.stream)),
            TVShelf(id: "offline", title: String(localized: "Offline"), style: .channels, items: offline),
        ])
        if favorites.isEmpty {
            stateView.show(
                symbol: "star",
                title: String(localized: "No favorites yet"),
                message: String(localized: "Press and hold any stream and choose Add to Favorites. Channels you star in Embr on iPhone show up here too.")
            )
        }
    }
}
