import Foundation

enum Secrets {
    static let twitchClientID = "YOUR_TWITCH_CLIENT_ID"
    static let workerBaseURL = "https://embr.YOUR_SUBDOMAIN.workers.dev"
    static let redirectURI = "embr://auth/callback"

    /// Optional. The HTTPS OAuth callback registered with the Twitch app. Leave empty
    /// to derive it from `workerBaseURL` (`<workerBaseURL>/auth/callback`). Set it only
    /// when the OAuth callback lives on a different host than `workerBaseURL` — e.g. the
    /// `app-store-ready` Worker reuses the sideload Worker's already-registered callback
    /// so login works without registering a new redirect URI in the Twitch console.
    static let oauthCallbackURL = ""
}
