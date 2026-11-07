import UIKit
import SafariServices

extension UIViewController {
    /// Opens a web page the way the viewer chose in Settings: over this screen in Safari View Controller, or in their
    /// browser. Anything but http and https is ignored.
    func openWebLink(_ url: URL, settings: SettingsStore = .shared) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        guard settings.current.openLinksInApp else {
            UIApplication.shared.open(url)
            return
        }
        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = Theme.accent
        present(safari, animated: true)
    }
}
