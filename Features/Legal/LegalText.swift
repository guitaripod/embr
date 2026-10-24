import Foundation

enum LegalText {
    static let supportEmail = "guitaripod@gmail.com"
    static let lastUpdated = String(localized: "23 October 2026")

    static let termsURL = URL(string: "https://midgarcorp.cc/legal/embr/terms")!

    static let privacyURL = URL(string: "https://midgarcorp.cc/legal/embr/privacy")!

    static let termsTitle = String(localized: "Terms of Use")
    static let privacyTitle = String(localized: "Privacy Policy")

    static let terms = String(localized: """
    Embr is an independent, open-source client for watching Twitch streams and chat. It is not \
    affiliated with, endorsed by, or sponsored by Twitch Interactive, Inc. By using Embr you agree \
    to these terms and to Twitch's own Terms of Service and Community Guidelines.

    User-generated content
    Embr displays live chat and other content created by Twitch users. Embr does not create, endorse, \
    or control that content. There is zero tolerance for objectionable content or abusive behaviour. \
    Embr filters objectionable content automatically, and lets you mute keywords, report any message, \
    and block any user — blocked and reported users are hidden from your chat instantly and flagged to \
    the developer. Reports are reviewed and acted on within 24 hours: offending content is removed and \
    offending users are ejected. Twitch's own moderation and reporting tools also apply.

    Acceptable use
    Do not use Embr to harass, threaten, or abuse others, to post unlawful content, or to circumvent \
    Twitch's terms. Streams play through Twitch's official embedded player, including any advertising \
    Twitch serves.

    No warranty
    Embr is provided "as is", without warranty of any kind. Availability depends on Twitch's services \
    and may change at any time.
    """)

    static let privacy = String(localized: """
    Embr has no advertising and no tracking, and the developer does not sell or share your data. The \
    only usage counts it sends are anonymous and described under More Apps.

    What stays on your device
    Your settings, watch history, list of channels, and blocked or hidden users are stored only on \
    your device. Diagnostic logs are written to the app's private storage and never leave your device \
    unless you explicitly choose to share them.

    The Midgar ID
    Embr keeps an anonymous Midgar ID, a random identifier with no name, email address or other detail \
    about you, in your iCloud Keychain. It is created the first time the app starts and is shared with \
    Midgar's other apps on your devices, so a purchase is recognised everywhere.

    Tips
    Tips are optional, unlock nothing and are bought through Apple. When you leave a tip, the purchase \
    record from Apple (which tip, the price, the dates and your App Store country) is sent to Midgar's \
    own server together with your Midgar ID. Midgar never receives your payment details.

    More Apps
    The More Apps card in Settings sends anonymous counts of how often it is opened, shown and tapped. \
    They carry no identifier and are not linked to you.

    Sign in with Twitch
    If you choose to sign in, authentication happens through Twitch's official OAuth flow. Your Twitch \
    access token is stored in the device Keychain and is sent only to Twitch's own APIs (via a thin \
    proxy that keeps no copy of it) to load chat and your follows. You can log out at any time, which \
    removes the token from your device.

    Reports
    When you report or block a chat message or user, the message, its author, and your selected reason \
    are sent to the developer so the report can be reviewed and acted on. These reports do not include \
    your identity.

    Twitch and other services
    Video and chat come from Twitch, whose privacy policy governs the data Twitch collects when its \
    embedded player and services are used. Emotes come from 7TV, BetterTTV and FrankerFaceZ and recent \
    chat from recent-messages.robotty.de; they receive the channel name and your IP address.

    The full policy, including how to have your Midgar ID deleted, is at midgarcorp.cc/legal/embr/privacy.

    Contact
    Questions about privacy: \(supportEmail)
    """)
}
