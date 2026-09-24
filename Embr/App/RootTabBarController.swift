import UIKit
import Combine
import EmbrCore

@MainActor
final class RootTabBarController: UITabBarController {
    private let auth: AuthService
    private var cancellables = Set<AnyCancellable>()
    private var isLoggedIn = false
    private var hasBuiltTabs = false

    enum Tab: String, CaseIterable {
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

    private lazy var topTab = makeTab(.top, navigation: topNav)
    private lazy var favoritesTab = makeTab(.favorites, navigation: favoritesNav)
    private lazy var searchTab = makeTab(.search, navigation: searchNav)
    private lazy var settingsTab = makeTab(.settings, navigation: settingsNav)
    private var followingTab: UITab?

    private let liveSidebar = LiveSidebarModel()
    private lazy var liveGroup: UITabGroup = {
        let group = UITabGroup(
            title: String(localized: "Live Now"),
            image: UIImage(systemName: "dot.radiowaves.left.and.right"),
            identifier: "live",
            children: []
        ) { _ in Self.placeholder() }
        group.preferredPlacement = .sidebarOnly
        group.sidebarAppearance = .rootSection
        group.isHidden = true
        return group
    }()

    /// The iPad shows a sidebar with the channels live right now; the phone keeps its tab bar.
    private var usesSidebar: Bool { !OrientationCoordinator.isPhone }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        OrientationCoordinator.mask
    }

    #if DEBUG
    override var prefersStatusBarHidden: Bool {
        ScreenshotHarness.hidesStatusBar || super.prefersStatusBarHidden
    }

    override var childForStatusBarHidden: UIViewController? {
        ScreenshotHarness.hidesStatusBar ? nil : super.childForStatusBarHidden
    }
    #endif

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
        if usesSidebar {
            mode = .tabSidebar
            sidebar.delegate = self
        }
        rebuildTabs()
        bind()
        FollowedLiveService.shared.start(tabBar: self)
        FavoritesLiveMonitor.shared.start()
        if usesSidebar {
            liveSidebar.start()
            registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (controller: RootTabBarController, _) in
                controller.updateLiveRefresh()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateLiveRefresh()
    }

    func setFollowingBadge(_ count: Int) {
        followingTab?.badgeValue = count > 0 ? "\(count)" : nil
    }

    func select(_ tab: Tab) {
        guard let target = uiTab(for: tab), tabs.contains(where: { $0 === target }) else { return }
        if target !== selectedTab {
            closePlayback(in: selectedNavigationController)
        }
        selectedTab = target
    }

    /// Leaving a tab while a channel or video plays in it closes that page, so its stream does
    /// not go on playing out of sight and the tab bar it hid comes back.
    private func closePlayback(in navigation: UINavigationController?) {
        guard let navigation, navigation.viewControllers.contains(where: { $0 is PlaybackPage }) else { return }
        navigation.popToRootViewController(animated: false)
    }

    private var hidesChromeForPlayback = false
    private var restoresSidebar = false

    /// A playing video wants the whole window, so on iPad the floating tab bar and an open
    /// sidebar step aside while a channel or video is on screen and return when the viewer goes
    /// back to browsing. The phone's tab bar is already hidden by the push. UIKit is sensitive
    /// to the order: hiding the sidebar before the tab bar leaves a phantom bottom bar in the
    /// safe area, and showing the tab bar before the sidebar leaves the sidebar's inset behind.
    func beginPlayback() {
        guard usesSidebar, !hidesChromeForPlayback else { return }
        hidesChromeForPlayback = true
        restoresSidebar = !sidebar.isHidden
        setTabBarHidden(true, animated: false)
        sidebar.isHidden = true
    }

    func endPlayback() {
        guard hidesChromeForPlayback else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.hidesChromeForPlayback,
                  !(self.selectedNavigationController?.topViewController is PlaybackPage) else { return }
            self.hidesChromeForPlayback = false
            if self.restoresSidebar { self.sidebar.isHidden = false }
            self.setTabBarHidden(false, animated: false)
        }
    }

    var selectedNavigationController: UINavigationController? {
        selectedViewController as? UINavigationController
    }

    /// The tabs in the order they are shown, which the Go menu numbers.
    var orderedTabs: [Tab] {
        tabs.compactMap { shown in Tab.allCases.first { uiTab(for: $0) === shown } }
    }

    /// Whether a Go-menu command or keyboard shortcut has a tab to land on right now.
    func canSelect(_ tab: Tab) -> Bool {
        guard let target = uiTab(for: tab) else { return false }
        return tabs.contains { $0 === target }
    }

    private func uiTab(for tab: Tab) -> UITab? {
        switch tab {
        case .following: return followingTab
        case .favorites: return favoritesTab
        case .top: return topTab
        case .search: return searchTab
        case .settings: return settingsTab
        }
    }

    private func setFavoritesBadge(_ count: Int) {
        favoritesTab.badgeValue = count > 0 ? "\(count)" : nil
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
        guard usesSidebar else { return }
        liveSidebar.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.updateLiveGroup() }
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
        var tabs: [UITab] = []
        if isLoggedIn {
            let following = followingTab ?? makeFollowingTab()
            followingTab = following
            tabs.append(contentsOf: [following, favoritesTab, topTab])
        } else {
            followingTab = nil
            followingNav = nil
            tabs.append(contentsOf: [topTab, favoritesTab])
        }
        tabs.append(contentsOf: [searchTab, settingsTab])
        if usesSidebar { tabs.append(liveGroup) }
        let previous = selectedTab
        setTabs(tabs, animated: false)
        UIMenuSystem.main.setNeedsRebuild()
        if isLoggedIn, let followingTab {
            selectedTab = followingTab
        } else if let previous, tabs.contains(where: { $0 === previous }) {
            selectedTab = previous
        }
    }

    private func makeFollowingTab() -> UITab {
        let navigation = wrap(FollowingViewController())
        followingNav = navigation
        return makeTab(.following, navigation: navigation)
    }

    private func makeTab(_ tab: Tab, navigation: UINavigationController) -> UITab {
        let item = navigation.viewControllers.first?.tabBarItem
        let uiTab = UITab(title: item?.title ?? "", image: item?.image, identifier: tab.rawValue) { _ in navigation }
        uiTab.preferredPlacement = .fixed
        if #available(iOS 26.1, *) {
            uiTab.selectedImage = item?.selectedImage
        }
        return uiTab
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

    /// One sidebar row per live channel. Rows are reused by identifier so the sidebar keeps its
    /// scroll position and highlight while viewer counts change underneath.
    private func updateLiveGroup() {
        let existing = Dictionary(liveGroup.children.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        liveGroup.children = liveSidebar.entries.map { entry in
            let stream = entry.stream
            let identifier = "live." + stream.userID
            let tab = existing[identifier] ?? UITab(title: stream.userName, image: nil, identifier: identifier) { _ in Self.placeholder() }
            tab.title = stream.userName
            tab.subtitle = stream.gameName.isEmpty ? nil : stream.gameName
            tab.image = liveSidebar.avatars[stream.userID] ?? UIImage(systemName: "person.crop.circle.fill")
            tab.userInfo = entry
            tab.preferredPlacement = .sidebarOnly
            sidebar.reconfigureItem(for: tab)
            return tab
        }
        liveGroup.isHidden = liveGroup.children.isEmpty
    }

    /// Live rows open their channel in the current tab and are never selected themselves, so
    /// the view controller UIKit requires of every tab is never shown; it matches the
    /// background in case it ever flashes.
    private static func placeholder() -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = Theme.background
        return controller
    }

    private func updateLiveRefresh() {
        guard usesSidebar else { return }
        let visible = traitCollection.horizontalSizeClass == .regular && !sidebar.isHidden
        liveSidebar.setVisible(visible)
    }

    /// A sidebar channel opens on top of whatever tab is showing, replacing a channel already
    /// open there rather than stacking one channel on another.
    private func openLiveChannel(_ entry: LiveSidebarModel.Entry) {
        guard let navigation = selectedNavigationController else { return }
        let stream = entry.stream
        if let current = navigation.topViewController as? ChannelViewController {
            guard current.broadcasterID != stream.userID else { return }
            var stack = navigation.viewControllers
            stack.removeLast()
            stack.append(ChannelViewController(channel: StreamRouting.channel(from: stream)))
            navigation.setViewControllers(stack, animated: true)
            return
        }
        navigation.pushViewController(ChannelViewController(channel: StreamRouting.channel(from: stream)), animated: true)
    }
}

extension RootTabBarController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        if let entry = tab.userInfo as? LiveSidebarModel.Entry {
            Haptics.selection()
            openLiveChannel(entry)
            return false
        }
        if tab === selectedTab {
            scrollActiveToTop(tab.viewController)
        } else {
            closePlayback(in: selectedNavigationController)
        }
        return true
    }

    /// Reached only if UIKit selects a live row without first asking `shouldSelectTab`: the
    /// previous tab comes back and the channel opens in it all the same.
    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        guard let entry = selectedTab.userInfo as? LiveSidebarModel.Entry else { return }
        self.selectedTab = previousTab ?? tabs.first
        openLiveChannel(entry)
    }

    private func scrollActiveToTop(_ viewController: UIViewController?) {
        let root = (viewController as? UINavigationController)?.viewControllers.first ?? viewController
        guard let scrollable = root as? ScrollsToTop else { return }
        Haptics.selection()
        scrollable.scrollToTop()
    }
}

extension RootTabBarController: UITabBarController.Sidebar.Delegate {
    func tabBarController(
        _ tabBarController: UITabBarController,
        sidebarVisibilityWillChange sidebar: UITabBarController.Sidebar,
        animator: any UITabBarController.Sidebar.Animating
    ) {
        animator.addCompletion { [weak self] in
            self?.updateLiveRefresh()
        }
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        sidebar: UITabBarController.Sidebar,
        itemFor request: UITabSidebarItem.Request
    ) -> UITabSidebarItem {
        let item = UITabSidebarItem(request: request)
        styleLiveItem(item)
        return item
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        sidebar: UITabBarController.Sidebar,
        update item: UITabSidebarItem
    ) {
        styleLiveItem(item)
    }

    /// A live channel row: a round avatar, the category beneath the name, and a red dot with the
    /// viewer count at the trailing edge.
    private func styleLiveItem(_ item: UITabSidebarItem) {
        guard case .tab(let tab) = item.content, let entry = tab.userInfo as? LiveSidebarModel.Entry else { return }
        var content = item.defaultContentConfiguration()
        content.imageProperties.maximumSize = CGSize(width: 28, height: 28)
        content.imageProperties.reservedLayoutSize = CGSize(width: 28, height: 28)
        content.imageProperties.cornerRadius = 14
        content.secondaryTextProperties.color = Theme.secondaryText
        content.secondaryTextProperties.numberOfLines = 1
        item.contentConfiguration = content
        item.accessories = [.customView(configuration: .init(
            customView: LiveViewerCountView(count: entry.stream.viewerCount),
            placement: .trailing(),
            reservedLayoutWidth: .actual,
            tintColor: Theme.secondaryText,
            maintainsFixedSize: false
        ))]
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        sidebar: UITabBarController.Sidebar,
        contextMenuConfigurationFor tab: UITab
    ) -> UIContextMenuConfiguration? {
        guard let entry = tab.userInfo as? LiveSidebarModel.Entry,
              let host = selectedNavigationController?.topViewController else { return nil }
        let stream = entry.stream
        return ChannelActions.configuration(login: stream.userLogin, broadcasterID: stream.userID, name: stream.userName, from: host)
    }
}

/// A red live dot and the viewer count, trailing a sidebar channel row.
@MainActor
private final class LiveViewerCountView: UIStackView {
    init(count: Int) {
        super.init(frame: .zero)
        let dot = UIView()
        dot.backgroundColor = Theme.liveDot
        dot.layer.cornerRadius = 3.5
        dot.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = ViewerFormat.string(count)
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = Theme.secondaryText
        addArrangedSubview(dot)
        addArrangedSubview(label)
        axis = .horizontal
        alignment = .center
        spacing = 5
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "\(count) viewers")
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7)
        ])
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }
}

/// A screen that plays video: the iPad hides its tab bar and sidebar while one is on top.
@MainActor
protocol PlaybackPage: AnyObject {}

extension ChannelViewController: PlaybackPage {}
extension VideoViewController: PlaybackPage {}

@MainActor
protocol ScrollsToTop: AnyObject {
    func scrollToTop()
}

extension FollowingViewController: ScrollsToTop {}
extension FavoritesViewController: ScrollsToTop {}
extension TopViewController: ScrollsToTop {}
extension SearchViewController: ScrollsToTop {}
