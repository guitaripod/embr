import UIKit
import EmbrCore

/// Where a click, a long press or a link goes in the Apple TV app.
@MainActor
enum TVRouter {
    static func open(_ item: TVShelfItem, from controller: UIViewController) {
        switch item {
        case .stream(let stream):
            TVPlaybackCoordinator.play(.live(stream), from: controller)
        case .category(let category):
            push(TVCategoryViewController(category: category), from: controller)
        case .channel(let channel):
            if channel.isLive {
                TVPlaybackCoordinator.play(.channel(login: channel.login), from: controller)
            } else {
                openChannel(login: channel.login, from: controller)
            }
        case .video(let video):
            TVPlaybackCoordinator.play(.video(video), from: controller)
        case .clip(let clip):
            TVPlaybackCoordinator.play(.clip(clip), from: controller)
        }
    }

    static func openChannel(login: String, from controller: UIViewController) {
        push(TVChannelViewController(login: login), from: controller)
    }

    static func signIn(from controller: UIViewController) {
        let signIn = TVSignInViewController()
        signIn.modalPresentationStyle = .fullScreen
        topmost(from: controller).present(signIn, animated: true)
    }

    static func handle(_ link: EmbrLink, from root: UIViewController) {
        switch link {
        case .watch(let login):
            TVPlaybackCoordinator.play(.channel(login: login), from: root)
        case .channel(let login):
            topmost(from: root).dismiss(animated: false)
            openChannel(login: login, from: root)
        }
    }

    /// The long-press menu of a card.
    static func contextActions(for item: TVShelfItem, from controller: UIViewController) -> [UIMenuElement] {
        switch item {
        case .stream(let stream):
            return [
                UIAction(title: String(localized: "Watch"), image: UIImage(systemName: "play.fill")) { _ in
                    TVPlaybackCoordinator.play(.live(stream), from: controller)
                },
                UIAction(title: String(localized: "Open Channel"), image: UIImage(systemName: "person.crop.rectangle")) { _ in
                    openChannel(login: stream.userLogin, from: controller)
                },
                UIAction(title: String(localized: "Watch in Multiview"), image: UIImage(systemName: "rectangle.split.2x2")) { _ in
                    TVMultiviewViewController.present(starting: [stream], from: controller)
                },
                favoriteAction(id: stream.userID, login: stream.userLogin, name: stream.userName),
            ]
        case .channel(let channel):
            var actions: [UIMenuElement] = [
                UIAction(title: String(localized: "Open Channel"), image: UIImage(systemName: "person.crop.rectangle")) { _ in
                    openChannel(login: channel.login, from: controller)
                },
                favoriteAction(id: channel.id, login: channel.login, name: channel.name),
            ]
            if channel.isLive {
                actions.insert(UIAction(title: String(localized: "Watch"), image: UIImage(systemName: "play.fill")) { _ in
                    TVPlaybackCoordinator.play(.channel(login: channel.login), from: controller)
                }, at: 0)
            }
            return actions
        case .video(let video):
            return [
                UIAction(title: String(localized: "Play"), image: UIImage(systemName: "play.fill")) { _ in
                    TVPlaybackCoordinator.play(.video(video), from: controller)
                },
                UIAction(title: String(localized: "Open Channel"), image: UIImage(systemName: "person.crop.rectangle")) { _ in
                    openChannel(login: video.userLogin, from: controller)
                },
            ]
        case .category, .clip:
            return []
        }
    }

    private static func favoriteAction(id: String, login: String, name: String) -> UIAction {
        let favorite = FavoritesStore.shared.isFavorite(id)
        return UIAction(
            title: favorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"),
            image: UIImage(systemName: favorite ? "star.slash" : "star"),
            attributes: favorite ? .destructive : []
        ) { _ in
            FavoritesStore.shared.toggle(id: id, login: login, name: name)
        }
    }

    private static func push(_ destination: UIViewController, from controller: UIViewController) {
        if let navigation = controller.navigationController ?? (controller as? UINavigationController) {
            navigation.pushViewController(destination, animated: true)
            return
        }
        if let tabs = controller as? UITabBarController ?? controller.tabBarController,
           let navigation = tabs.selectedViewController as? UINavigationController {
            navigation.pushViewController(destination, animated: true)
            return
        }
        topmost(from: controller).present(UINavigationController(rootViewController: destination), animated: true)
    }

    static func topmost(from controller: UIViewController) -> UIViewController {
        var top = controller
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
