import UIKit

@MainActor
enum ChannelActions {
    static func menu(login: String, broadcasterID: String, name: String, from vc: UIViewController) -> UIMenu {
        UIMenu(children: [
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
        ])
    }

    static func configuration(login: String, broadcasterID: String, name: String, from vc: UIViewController) -> UIContextMenuConfiguration {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak vc] _ in
            guard let vc else { return nil }
            return menu(login: login, broadcasterID: broadcasterID, name: name, from: vc)
        }
    }
}
