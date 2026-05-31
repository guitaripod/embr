import UIKit
import Combine
import EmbrCore

@MainActor
final class RootTabBarController: UITabBarController {
    private let auth: AuthService
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private var cancellables = Set<AnyCancellable>()
    private var isLoggedIn = false
    private var hasBuiltTabs = false

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
    }

    private func bind() {
        auth.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                MainActor.assumeIsolated { self?.handle(state) }
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
    }

    private func rebuildTabs() {
        hasBuiltTabs = true
        var controllers: [UIViewController] = []
        if isLoggedIn {
            controllers.append(wrap(FollowingViewController()))
        }
        controllers.append(wrap(TopViewController()))
        controllers.append(wrap(SearchViewController()))
        controllers.append(wrap(SettingsViewController()))
        setViewControllers(controllers, animated: false)
    }

    private func wrap(_ controller: UIViewController) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: controller)
        navigation.navigationBar.prefersLargeTitles = true
        navigation.tabBarItem = controller.tabBarItem
        applyNavigationBarAppearance(to: navigation.navigationBar)
        return navigation
    }

    private func applyBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.backgroundColor = Theme.background.withAlphaComponent(0.6)
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = Theme.accent
    }

    private func applyNavigationBarAppearance(to navigationBar: UINavigationBar) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.backgroundColor = Theme.background.withAlphaComponent(0.6)
        navigationBar.standardAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.tintColor = Theme.accent
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
        selectionFeedback.selectionChanged()
        scrollable.scrollToTop()
    }
}

@MainActor
protocol ScrollsToTop: AnyObject {
    func scrollToTop()
}

extension FollowingViewController: ScrollsToTop {}
extension TopViewController: ScrollsToTop {}
extension SearchViewController: ScrollsToTop {}
