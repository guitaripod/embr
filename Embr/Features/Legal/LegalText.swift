import Foundation

enum LegalText {
    static let supportEmail = "guitaripod@gmail.com"
    static let lastUpdated = "26 June 2026"

    static var termsURL: URL {
        Configuration.current.workerBaseURL.appendingPathComponent("legal/terms")
    }

    static var privacyURL: URL {
        Configuration.current.workerBaseURL.appendingPathComponent("legal/privacy")
    }

    static let termsTitle = "Terms of Use"
    static let privacyTitle = "Privacy Policy"

    static let terms = """
    Embr is an independent, open-source client for watching Twitch streams and chat. It is not \
    affiliated with, endorsed by, or sponsored by Twitch Interactive, Inc. By using Embr you agree \
    to these terms and to Twitch's own Terms of Service and Community Guidelines.

    User-generated content
    Embr displays live chat and other content created by Twitch users. Embr does not create, endorse, \
    or control that content. There is zero tolerance for objectionable content or abusive behaviour. \
    You can report any message from within the app, and you can block or hide any user. Reported \
    content and users are reviewed, and offending users may be ejected from the service. Twitch's own \
    moderation and reporting tools also apply.

    Acceptable use
    Do not use Embr to harass, threaten, or abuse others, to post unlawful content, or to circumvent \
    Twitch's terms. Streams play through Twitch's official embedded player, including any advertising \
    Twitch serves.

    No warranty
    Embr is provided "as is", without warranty of any kind. Availability depends on Twitch's services \
    and may change at any time.
    """

    static let privacy = """
    Embr is designed to collect as little data as possible. The developer does not operate any \
    advertising or analytics tracking, and does not sell or share your data.

    What stays on your device
    Your settings, watch history, list of channels, and blocked or hidden users are stored only on \
    your device. Diagnostic logs are written to the app's private storage and never leave your device \
    unless you explicitly choose to share them.

    Sign in with Twitch
    If you choose to sign in, authentication happens through Twitch's official OAuth flow. Your Twitch \
    access token is stored in the device Keychain and is sent only to Twitch's own APIs (via a thin \
    proxy that keeps no copy of it) to load chat and your follows. You can log out at any time, which \
    removes the token from your device.

    Reports
    When you report a chat message, the reported message, its author, and your selected reason are sent \
    to the developer so the report can be reviewed. Reports do not include your identity.

    Twitch
    Video and chat come from Twitch. Twitch's own privacy policy governs the data Twitch collects when \
    its embedded player and services are used.

    Contact
    Questions about privacy: \(supportEmail)
    """
}
