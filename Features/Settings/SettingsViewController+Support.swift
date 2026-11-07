import UIKit
import SafariServices
import MidgarKit

/// The About and Support section's actions: tips, sharing the app and its logs, the source code and support email.
extension SettingsViewController {
    /// The App Store's own localized name and price for a tip. The DEBUG screenshot preview
    /// substitutes fixed US-priced rows because a simulator launched by `simctl` has no
    /// StoreKit configuration to answer from.
    func tipLabels(for id: String) -> (String, String?) {
        if let product = TipJarStore.shared.product(id: id) {
            return (product.displayName, product.displayPrice)
        }
        #if DEBUG
        if ScreenshotHarness.previewTips, let index = TipJarStore.productIDs.firstIndex(of: id) {
            let previews = [
                (String(localized: "Small Tip"), "$1.99"),
                (String(localized: "Medium Tip"), "$4.99"),
                (String(localized: "Large Tip"), "$9.99"),
            ]
            return previews[index]
        }
        #endif
        return (String(localized: "Tip"), nil)
    }

    static var versionString: String {
        MidgarVersionInfo().display
    }

    func openGitHub() {
        guard let url = URL(string: "https://github.com/guitaripod/embr") else { return }
        if store.current.openLinksInApp {
            let safari = SFSafariViewController(url: url)
            safari.preferredControlTintColor = Theme.accent
            present(safari, animated: true)
        } else {
            UIApplication.shared.open(url)
        }
    }

    func shareLogs(from sourceView: UIView?) {
        let urls = MidgarLog.logFileURLs
        guard !urls.isEmpty else {
            let alert = UIAlertController(title: String(localized: "No Logs Yet"), message: String(localized: "Diagnostic logs will appear here after you use the app."), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
            present(alert, animated: true)
            return
        }
        let activity = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = sourceView ?? view
            popover.sourceRect = (sourceView ?? view).bounds
        }
        present(activity, animated: true)
    }

    func shareApp(from sourceView: UIView?) {
        let activity = UIActivityViewController(activityItems: AppStoreLinks.shareItems, applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = sourceView ?? view
            popover.sourceRect = (sourceView ?? view).bounds
        }
        present(activity, animated: true)
    }

    func leaveTip(_ id: String) {
        guard let product = TipJarStore.shared.product(id: id) else { return }
        collectionView.isUserInteractionEnabled = false
        Task { [weak self] in
            let outcome = await TipJarStore.shared.purchase(product, in: self?.view.window?.windowScene)
            guard let self else { return }
            self.collectionView.isUserInteractionEnabled = true
            self.presentTipOutcome(outcome)
        }
    }

    private func presentTipOutcome(_ outcome: TipJarStore.Outcome) {
        let title: String
        let message: String
        switch outcome {
        case .thanked:
            Haptics.notify(.success)
            title = String(localized: "Thank You!")
            message = String(localized: "Your tip keeps Embr going.")
        case .pending:
            title = String(localized: "Waiting for Approval")
            message = String(localized: "Your tip will go through once it's approved.")
        case let .failed(reason):
            Haptics.notify(.error)
            title = String(localized: "Couldn't Complete the Tip")
            message = reason
        case .cancelled:
            return
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }

    func openSupportEmail() {
        let subject = String(localized: "Embr Support (\(Self.versionString))")
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = LegalText.supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        guard let url = components.url else {
            presentSupportFallback()
            return
        }
        UIApplication.shared.open(url) { [weak self] success in
            guard !success else { return }
            self?.presentSupportFallback()
        }
    }

    private func presentSupportFallback() {
        UIPasteboard.general.string = LegalText.supportEmail
        let alert = UIAlertController(
            title: String(localized: "Contact Support"),
            message: String(localized: "Email \(LegalText.supportEmail)\n\nThe address has been copied to your clipboard."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }
}
