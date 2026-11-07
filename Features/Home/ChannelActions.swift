import UIKit

@MainActor
enum ChannelActions {
    static func menu(login: String, broadcasterID: String, name: String, from vc: UIViewController, extraActions: [UIAction] = []) -> UIMenu {
        UIMenu(children: [
            favoriteAction(login: login, broadcasterID: broadcasterID, name: name),
            openInChatsAction(login: login, broadcasterID: broadcasterID, name: name, from: vc),
            UIAction(title: String(localized: "View Profile"), image: UIImage(systemName: "person.crop.circle")) { [weak vc] _ in
                guard let vc else { return }
                vc.present(ProfileSheetViewController(login: login, navigator: vc.navigationController), animated: true)
            },
            UIAction(title: String(localized: "Videos & Clips"), image: UIImage(systemName: "film.stack")) { [weak vc] _ in
                vc?.navigationController?.pushViewController(
                    ChannelVideosViewController(broadcasterID: broadcasterID, channelName: name),
                    animated: true
                )
            }
        ] + extraActions)
    }

    static func configuration(
        login: String,
        broadcasterID: String,
        name: String,
        from vc: UIViewController,
        extraActions: [UIAction] = []
    ) -> UIContextMenuConfiguration {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak vc] _ in
            guard let vc else { return nil }
            return menu(login: login, broadcasterID: broadcasterID, name: name, from: vc, extraActions: extraActions)
        }
    }

    /// A channel dragged out of a list carries its twitch.tv link, so on iPad it drops into
    /// Messages, Notes or Safari as the channel's page.
    static func dragItems(login: String, name: String) -> [UIDragItem] {
        guard let url = URL(string: "https://www.twitch.tv/\(login)") else { return [] }
        let provider = NSItemProvider(object: url as NSURL)
        provider.suggestedName = name
        let item = UIDragItem(itemProvider: provider)
        item.localObject = login
        return [item]
    }

    /// Keeps the channel's chat open in the Chats tab and goes there.
    private static func openInChatsAction(login: String, broadcasterID: String, name: String, from vc: UIViewController) -> UIAction {
        UIAction(title: String(localized: "Open in Chats"), image: UIImage(systemName: "bubble.left.and.bubble.right")) { [weak vc] _ in
            ChatsModel.shared.open(ChatsModel.Entry(id: broadcasterID, login: login, name: name))
            Haptics.selection()
            let root = (vc as? RootTabBarController) ?? (vc?.tabBarController as? RootTabBarController)
            root?.select(.chats)
        }
    }

    private static func favoriteAction(login: String, broadcasterID: String, name: String) -> UIAction {
        let favorites = FavoritesStore.shared
        let isFavorite = favorites.isFavorite(broadcasterID)
        return UIAction(
            title: isFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"),
            image: UIImage(systemName: isFavorite ? "star.slash" : "star"),
            attributes: isFavorite ? .destructive : []
        ) { _ in
            favorites.toggle(id: broadcasterID, login: login, name: name)
            Haptics.notify(.success)
        }
    }
}
