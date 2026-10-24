import Foundation
import EmbrCore

struct Configuration: Sendable {
    let twitchClientID: String
    /// Where Embr's worker answers: the `embr` route of the Midgar gateway.
    let workerBaseURL: URL
    let redirectURI: String
    let recentMessagesBaseURL: URL

    /// The redirect URI registered in the Twitch console for the shipped app. Twitch sends the browser there inside
    /// `ASWebAuthenticationSession`, which is a navigation and not an app network call, so it stays on the worker's own
    /// host and the worker bounces it to `embr://auth/callback`. Changing it needs a console change first.
    var twitchRedirectURI: String {
        "https://embr.guitaripod.workers.dev/auth/callback"
    }

    static let current = Configuration(
        twitchClientID: Secrets.twitchClientID,
        workerBaseURL: MidgarGatewayTransport.routeBaseURL,
        redirectURI: Secrets.redirectURI,
        recentMessagesBaseURL: URL(string: "https://recent-messages.robotty.de/api/v2")!
    )
}

@MainActor
final class AppContainer {
    static let shared = AppContainer()

    let configuration = Configuration.current
    let transport: HTTPTransport = URLSessionTransport.shared
    let auth = AuthService.shared
    let api = TwitchAPIClient.shared
    let emotes = EmoteService.shared
    let images: ImageLoading = ImageLoader.shared
    let playback = PlaybackResolver.shared
    let database = DatabaseManager.shared
    let settings = SettingsStore.shared

    private init() {}

    func makeChatRoom(channel: ChannelInfo, loggedIn: Bool) -> ChatRoom {
        ChatRoom(
            channel: channel,
            loggedIn: loggedIn,
            api: api,
            auth: auth,
            emotes: emotes,
            recentMessages: RecentMessagesClient.shared
        )
    }
}
