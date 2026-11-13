import UIKit
import MidgarKit

/// The Help & Feedback and About pages and their actions: the support email, sharing the logs and the app, the
/// source code. Each action presents from the page the row was tapped on, which is the one on screen.
extension SettingsViewController {
    func helpSections() -> [SettingsSection] {
        [
            SettingsSection(id: "help.contact", items: [
                SettingsItem(id: "contactSupport", title: String(localized: "Contact Support"), keywords: [String(localized: "Email"), String(localized: "Help")], kind: .action(role: .accent) { [weak self] presenter, _ in
                    self?.openSupportEmail(from: presenter)
                }),
                SettingsItem(id: "shareLogs", title: String(localized: "Share Diagnostic Logs"), kind: .action(role: .accent) { [weak self] presenter, source in
                    self?.shareLogs(from: presenter, source: source)
                }),
            ]),
            SettingsSection(id: "help.share", items: [
                SettingsItem(id: "rateApp", title: String(localized: "Rate Embr"), kind: .action(role: .accent) { _, _ in
                    UIApplication.shared.open(AppStoreLinks.writeReview)
                }),
                SettingsItem(id: "shareApp", title: String(localized: "Share Embr"), kind: .action(role: .accent) { [weak self] presenter, source in
                    self?.shareApp(from: presenter, source: source)
                }),
            ]),
        ]
    }

    func aboutSections() -> [SettingsSection] {
        [
            SettingsSection(id: "about.app", footer: String(localized: "Embr is an independent, open-source Twitch client. Not affiliated with Twitch."), items: [
                SettingsItem(id: "version", title: String(localized: "Version"), kind: .value(Self.versionString)),
                SettingsItem(id: "github", title: String(localized: "GitHub"), keywords: [String(localized: "Source Code")], kind: .link(value: nil) { [weak self] presenter in
                    self?.openGitHub(from: presenter)
                }),
                SettingsItem(id: "termsOfUse", title: String(localized: "Terms of Use"), kind: .link(value: nil) { [weak self] presenter in
                    self?.push(LegalViewController(title: LegalText.termsTitle, body: LegalText.terms), from: presenter)
                }),
                SettingsItem(id: "privacyPolicy", title: String(localized: "Privacy Policy"), kind: .link(value: nil) { [weak self] presenter in
                    self?.push(LegalViewController(title: LegalText.privacyTitle, body: LegalText.privacy), from: presenter)
                }),
            ]),
        ]
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
