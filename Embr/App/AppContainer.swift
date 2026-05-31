import Foundation
import EmbrCore

struct Configuration: Sendable {
    let twitchClientID: String
    let workerBaseURL: URL
    let redirectURI: String
    let recentMessagesBaseURL: URL

    static let current = Configuration(
        twitchClientID: Secrets.twitchClientID,
        workerBaseURL: URL(string: Secrets.workerBaseURL) ?? URL(string: "https://embr.example.workers.dev")!,
        redirectURI: Secrets.redirectURI,
        recentMessagesBaseURL: URL(string: "https://recent-messages.robotty.de/api/v2")!
    )
}

@MainActor
final class AppContainer {
    static let shared = AppContainer()

    let logger = AppLogger.shared
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
