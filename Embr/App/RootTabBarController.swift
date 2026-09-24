import UIKit
import Combine
import EmbrCore

@MainActor
final class RootTabBarController: UITabBarController {
    private let auth: AuthService
    private var cancellables = Set<AnyCancellable>()
    private var isLoggedIn = false
    private var hasBuiltTabs = false

    enum Tab {
        case following
        case favorites
        case top
        case search
        case settings
    }

    private lazy var topNav = wrap(TopViewController())
    private lazy var favoritesNav = wrap(FavoritesViewController())
    private lazy var searchNav = wrap(SearchViewController())
    private lazy var settingsNav = wrap(SettingsViewController())
    private var followingNav: UINavigationController?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        OrientationCoordinator.mask
    }

    init(auth: AuthService = AuthService.shared) {
        self.auth = auth
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        applyBarAppearance()
        rebuildTabs()
        bind()
        FollowedLiveService.shared.start(tabBar: self)
        FavoritesLiveMonitor.shared.start()
    }

    func setFollowingBadge(_ count: Int) {
        followingNav?.tabBarItem.badgeValue = count > 0 ? "\(count)" : nil
    }

    func select(_ tab: Tab) {
        let target: UINavigationController?
        switch tab {
        case .following: target = followingNav
        case .favorites: target = favoritesNav
        case .top: target = topNav
        case .search: target = searchNav
        case .settings: target = settingsNav
        }
        guard let target, viewControllers?.contains(where: { $0 === target }) == true else { return }
        selectedViewController = target
    }

    private func setFavoritesBadge(_ count: Int) {
        favoritesNav.tabBarItem.badgeValue = count > 0 ? "\(count)" : nil
    }

    private func bind() {
        auth.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                MainActor.assumeIsolated { self?.handle(state) }
            }
            .store(in: &cancellables)
        FavoritesLiveMonitor.shared.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.setFavoritesBadge(FavoritesLiveMonitor.shared.liveCount) }
            }
            .store(in: &cancellables)
    }

    private func handle(_ state: AuthState) {
        let loggedIn: Bool
        switch state {
        case .anonymous: loggedIn = false
        case .authenticated: loggedIn = true
        }
        guard loggedIn != isLoggedIn || !hasBuiltTabs else { return }
        isLoggedIn = loggedIn
        rebuildTabs()
        if loggedIn {
            FollowedLiveService.shared.refreshForced()
        } else {
            FollowedLiveService.shared.reset()
        }
    }

    /// Signed in: Following leads and Favorites sits beside it. Signed out: Top leads, so a
    /// first launch opens on something to watch rather than an empty Favorites list.
    private func rebuildTabs() {
        hasBuiltTabs = true
        var controllers: [UIViewController] = []
        if isLoggedIn {
            let following = followingNav ?? wrap(FollowingViewController())
            followingNav = following
            controllers.append(contentsOf: [following, favoritesNav, topNav])
        } else {
            followingNav = nil
            controllers.append(contentsOf: [topNav, favoritesNav])
        }
        controllers.append(contentsOf: [searchNav, settingsNav])
        let previous = selectedViewController
        setViewControllers(controllers, animated: false)
        if isLoggedIn, let following = followingNav {
            selectedViewController = following
        } else if let previous, controllers.contains(where: { $0 === previous }) {
            selectedViewController = previous
        }
    }

    private func wrap(_ controller: UIViewController) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: controller)
        navigation.navigationBar.prefersLargeTitles = true
        navigation.navigationBar.tintColor = Theme.accent
        navigation.tabBarItem = controller.tabBarItem
        return navigation
    }

    private func applyBarAppearance() {
        tabBar.tintColor = Theme.accent
    }
}

extension RootTabBarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if viewController === selectedViewController {
            scrollActiveToTop(viewController)
        }
        return true
    }

    private func scrollActiveToTop(_ viewController: UIViewController) {
        let root = (viewController as? UINavigationController)?.viewControllers.first ?? viewController
        guard let scrollable = root as? ScrollsToTop else { return }
        Haptics.selection()
        scrollable.scrollToTop()
    }
}

@MainActor
protocol ScrollsToTop: AnyObject {
    func scrollToTop()
}

extension FollowingViewController: ScrollsToTop {}
extension FavoritesViewController: ScrollsToTop {}
extension TopViewController: ScrollsToTop {}
extension SearchViewController: ScrollsToTop {}
