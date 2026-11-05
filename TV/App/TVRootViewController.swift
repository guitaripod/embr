import UIKit
import EmbrCore

/// The tab bar across the top of the Apple TV app: Following, Favorites, Browse, Search and Settings.
final class TVRootViewController: UITabBarController {
    init() {
        super.init(nibName: nil, bundle: nil)
        tabs = [
            UITab(title: String(localized: "Following"), image: UIImage(systemName: "person.2"), identifier: Settings.StartTab.following.rawValue) { _ in
                Self.navigation(TVFollowingViewController())
            },
            UITab(title: String(localized: "Favorites"), image: UIImage(systemName: "star"), identifier: Settings.StartTab.favorites.rawValue) { _ in
                Self.navigation(TVFavoritesViewController())
            },
            UITab(title: String(localized: "Browse"), image: UIImage(systemName: "square.grid.2x2"), identifier: Settings.StartTab.top.rawValue) { _ in
                Self.navigation(TVBrowseViewController())
            },
            UISearchTab { _ in
                TVSearch.makeTab()
            },
            UITab(title: String(localized: "Settings"), image: UIImage(systemName: "gearshape"), identifier: "settings") { _ in
                UINavigationController(rootViewController: TVSettingsViewController())
            },
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Opens on the tab the person chose in Settings; someone not signed in starts on Favorites when they have any, else
    /// on Browse.
    func selectStartTab(signedIn: Bool) {
        var start = SettingsStore.shared.current.startTabPreference
        if start == .following, !signedIn {
            start = FavoritesStore.shared.channels.isEmpty ? .top : .favorites
        }
        if let tab = tabs.first(where: { $0.identifier == start.rawValue }) {
            selectedTab = tab
        }
    }

    private static func navigation(_ root: UIViewController) -> UINavigationController {
        UINavigationController(rootViewController: root)
    }
}
