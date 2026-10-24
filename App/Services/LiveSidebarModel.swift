import UIKit
import Combine
import EmbrCore

/// The channels live right now, for the iPad sidebar: live favorites first, then live follows,
/// each with a round avatar once it has loaded. While the sidebar is on screen it rechecks
/// every two minutes, so the list does not go stale during a long session.
@MainActor
final class LiveSidebarModel {
    struct Entry: Equatable {
        let stream: LiveStream
        let isFavorite: Bool
    }

    let changes = PassthroughSubject<Void, Never>()
    private(set) var entries: [Entry] = []
    private(set) var avatars: [String: UIImage] = [:]

    private let favorites: FavoritesLiveMonitor
    private let followed: FollowedLiveService
    private let api: TwitchAPIProviding
    private let images: ImageLoading
    private var avatarURLs: [String: URL] = [:]
    private var requestedAvatars: Set<String> = []
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    private static let limit = 30
    private static let refreshInterval: TimeInterval = 120
    private static let avatarSide: CGFloat = 28

    init(
        favorites: FavoritesLiveMonitor = .shared,
        followed: FollowedLiveService = .shared,
        api: TwitchAPIProviding = TwitchAPIClient.shared,
        images: ImageLoading = ImageLoader.shared
    ) {
        self.favorites = favorites
        self.followed = followed
        self.api = api
        self.images = images
    }

    func start() {
        guard cancellables.isEmpty else { return }
        favorites.changes
            .merge(with: followed.changes)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.rebuild() }
            }
            .store(in: &cancellables)
        rebuild()
    }

    /// Keeps the live list fresh only while someone can see it; both sources throttle to one
    /// network check a minute on their own.
    func setVisible(_ visible: Bool) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard visible else { return }
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSources() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func refreshSources() {
        guard UIApplication.shared.applicationState == .active else { return }
        favorites.refresh(force: false)
        followed.refreshNow()
    }

    private func rebuild() {
        let favoriteStreams = favorites.liveStreams
        let favoriteIDs = Set(favoriteStreams.map(\.userID))
        let followedStreams = followed.liveStreams
            .filter { !favoriteIDs.contains($0.userID) }
            .sorted { $0.viewerCount > $1.viewerCount }
        let combined = favoriteStreams.map { Entry(stream: $0, isFavorite: true) }
            + followedStreams.map { Entry(stream: $0, isFavorite: false) }
        entries = Array(combined.prefix(Self.limit))
        avatarURLs.merge(favorites.avatars) { current, _ in current }
        changes.send()
        loadAvatars()
    }

    private func loadAvatars() {
        let missing = entries.map(\.stream.userID).filter { avatars[$0] == nil && !requestedAvatars.contains($0) }
        guard !missing.isEmpty else { return }
        requestedAvatars.formUnion(missing)
        Task { [weak self] in
            guard let self else { return }
            let unknown = missing.filter { self.avatarURLs[$0] == nil }
            if !unknown.isEmpty, let users = try? await self.api.users(ids: unknown) {
                for user in users {
                    if let url = user.profileImageURL { self.avatarURLs[user.id] = url }
                }
            }
            for id in missing {
                guard let url = self.avatarURLs[id],
                      let image = await self.images.image(for: url, targetScale: 3) else {
                    self.requestedAvatars.remove(id)
                    continue
                }
                self.avatars[id] = Self.roundAvatar(image)
            }
            self.changes.send()
        }
    }

    /// Clipped to a circle ahead of time and marked original, so the sidebar neither tints it
    /// nor shows a square photo.
    private static func roundAvatar(_ image: UIImage) -> UIImage {
        let side = avatarSide
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 3
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: side, height: side)).addClip()
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return rendered.withRenderingMode(.alwaysOriginal)
    }
}
