import UIKit
import MidgarKit

/// The Support and About pages' actions: tips, sharing the app and its logs, the source code and support email. Each
/// presents from the page the row was tapped on, which is the one on screen.
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

    func openGitHub(from presenter: UIViewController) {
        guard let url = URL(string: "https://github.com/guitaripod/embr") else { return }
        presenter.openWebLink(url)
    }

    func shareLogs(from presenter: UIViewController, source sourceView: UIView?) {
        let urls = MidgarLog.logFileURLs
        guard !urls.isEmpty else {
            let alert = UIAlertController(title: String(localized: "No Logs Yet"), message: String(localized: "Diagnostic logs will appear here after you use the app."), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
            presenter.present(alert, animated: true)
            return
        }
        present(UIActivityViewController(activityItems: urls, applicationActivities: nil), from: presenter, source: sourceView)
    }

    func shareApp(from presenter: UIViewController, source sourceView: UIView?) {
        present(UIActivityViewController(activityItems: AppStoreLinks.shareItems, applicationActivities: nil), from: presenter, source: sourceView)
    }

    private func present(_ activity: UIActivityViewController, from presenter: UIViewController, source sourceView: UIView?) {
        if let popover = activity.popoverPresentationController {
            popover.sourceView = sourceView ?? presenter.view
            popover.sourceRect = (sourceView ?? presenter.view).bounds
        }
        presenter.present(activity, animated: true)
    }

    func leaveTip(_ id: String, from presenter: UIViewController) {
        guard let product = TipJarStore.shared.product(id: id) else { return }
        presenter.view.isUserInteractionEnabled = false
        Task { [weak self, weak presenter] in
            let outcome = await TipJarStore.shared.purchase(product, in: presenter?.view.window?.windowScene)
            guard let self, let presenter else { return }
            presenter.view.isUserInteractionEnabled = true
            self.presentTipOutcome(outcome, from: presenter)
        }
    }

    private func presentTipOutcome(_ outcome: TipJarStore.Outcome, from presenter: UIViewController) {
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
        presenter.present(alert, animated: true)
    }

    func openSupportEmail(from presenter: UIViewController) {
        let subject = String(localized: "Embr Support (\(Self.versionString))")
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = LegalText.supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        guard let url = components.url else {
            presentSupportFallback(from: presenter)
            return
        }
        UIApplication.shared.open(url) { [weak self, weak presenter] success in
            guard !success, let presenter else { return }
            self?.presentSupportFallback(from: presenter)
        }
    }

    private func presentSupportFallback(from presenter: UIViewController) {
        UIPasteboard.general.string = LegalText.supportEmail
        let alert = UIAlertController(
            title: String(localized: "Contact Support"),
            message: String(localized: "Email \(LegalText.supportEmail)\n\nThe address has been copied to your clipboard."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        presenter.present(alert, animated: true)
    }
}
