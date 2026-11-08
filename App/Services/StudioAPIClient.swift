import Foundation
import EmbrCore
import MidgarCore

/// Studio's calls to Twitch for the streamer's own channel or one they moderate. A protocol, so the sample stream and
/// tests stand in for Twitch.
protocol StudioAPI: Sendable {
    func adSchedule(broadcasterID: String) async throws -> AdSchedule?
    func snoozeNextAd(broadcasterID: String, previous: AdSchedule?) async throws -> AdSchedule?
    func startCommercial(broadcasterID: String, length: Int) async throws -> CommercialResult?
    func hypeTrain(broadcasterID: String) async throws -> StudioHypeTrain?
    func activePoll(broadcasterID: String) async throws -> StudioPoll?
    func activePrediction(broadcasterID: String) async throws -> StudioPrediction?
    func goals(broadcasterID: String) async throws -> [StudioGoal]
    func followers(broadcasterID: String) async throws -> (total: Int, recent: [StudioFollow])
    func liveStream(broadcasterID: String) async throws -> LiveStream?
    func user(id: String) async throws -> TwitchUser?
    func schedule(broadcasterID: String) async throws -> [ScheduleSegment]
    func moderatedChannels(userID: String) async throws -> [ModeratedChannel]
    func shoutout(fromBroadcasterID: String, toBroadcasterID: String, moderatorID: String) async throws
    func pin(broadcasterID: String, moderatorID: String, messageID: String) async throws
    func changeChatMode(broadcasterID: String, moderatorID: String, change: ChatModeChange) async throws
    func setShieldMode(broadcasterID: String, moderatorID: String, active: Bool) async throws
    func shieldModeActive(broadcasterID: String, moderatorID: String) async throws -> Bool?
}

final class StudioAPIClient: StudioAPI {
    static let shared = StudioAPIClient()

    private let transport: HTTPTransport
    private let auth: AuthControlling
    private let factory: HelixRequestFactory
    private let browse: TwitchAPIProviding

    init(
        transport: HTTPTransport = URLSessionTransport.shared,
        auth: AuthControlling = AuthService.shared,
        clientID: String = Configuration.current.twitchClientID,
        browse: TwitchAPIProviding = TwitchAPIClient.shared
    ) {
        self.transport = transport
        self.auth = auth
        self.factory = HelixRequestFactory(clientID: clientID)
        self.browse = browse
    }

    func adSchedule(broadcasterID: String) async throws -> AdSchedule? {
        let response = try await perform(factory.adSchedule(broadcasterID: broadcasterID, token: token()))
        return StudioHelixDecoder.adSchedule(response.body, fetchedAt: Date())
    }

    func snoozeNextAd(broadcasterID: String, previous: AdSchedule?) async throws -> AdSchedule? {
        let response = try await perform(factory.snoozeNextAd(broadcasterID: broadcasterID, token: token()))
        return StudioHelixDecoder.snoozed(response.body, previous: previous, fetchedAt: Date())
    }

    func startCommercial(broadcasterID: String, length: Int) async throws -> CommercialResult? {
        let response = try await perform(factory.startCommercial(broadcasterID: broadcasterID, length: length, token: token()))
        return StudioHelixDecoder.commercial(response.body)
    }

    func hypeTrain(broadcasterID: String) async throws -> StudioHypeTrain? {
        let response = try await perform(factory.hypeTrainStatus(broadcasterID: broadcasterID, token: token()))
        return StudioHelixDecoder.hypeTrain(response.body)
    }

    func activePoll(broadcasterID: String) async throws -> StudioPoll? {
        let response = try await perform(factory.polls(broadcasterID: broadcasterID, token: token()))
        return StudioHelixDecoder.activePoll(response.body)
    }

    func activePrediction(broadcasterID: String) async throws -> StudioPrediction? {
        let response = try await perform(factory.predictions(broadcasterID: broadcasterID, token: token()))
        return StudioHelixDecoder.activePrediction(response.body)
    }

    func goals(broadcasterID: String) async throws -> [StudioGoal] {
        let response = try await perform(factory.creatorGoals(broadcasterID: broadcasterID, token: token()))
        return StudioHelixDecoder.goals(response.body)
    }

    func followers(broadcasterID: String) async throws -> (total: Int, recent: [StudioFollow]) {
        let response = try await perform(factory.channelFollowers(broadcasterID: broadcasterID, first: 20, token: token()))
        return StudioHelixDecoder.followers(response.body)
    }

    func liveStream(broadcasterID: String) async throws -> LiveStream? {
        try await browse.streams(userIDs: [broadcasterID]).first
    }

    func user(id: String) async throws -> TwitchUser? {
        try await browse.users(ids: [id]).first
    }

    func schedule(broadcasterID: String) async throws -> [ScheduleSegment] {
        do {
            return try await TwitchAPIClient.shared.schedule(broadcasterID: broadcasterID)
        } catch APIError.notFound {
            return []
        }
    }

    func moderatedChannels(userID: String) async throws -> [ModeratedChannel] {
        let token = try await token()
        var channels: [ModeratedChannel] = []
        var cursor: String?
        for _ in 0..<10 {
            let response = try await perform(factory.moderatedChannels(userID: userID, after: cursor, token: token))
            let page = StudioHelixDecoder.moderatedChannels(response.body)
            channels += page.channels
            cursor = page.cursor
            if cursor == nil { break }
        }
        return channels
    }

    func shoutout(fromBroadcasterID: String, toBroadcasterID: String, moderatorID: String) async throws {
        _ = try await perform(factory.shoutout(fromBroadcasterID: fromBroadcasterID, toBroadcasterID: toBroadcasterID, moderatorID: moderatorID, token: token()))
    }

    func pin(broadcasterID: String, moderatorID: String, messageID: String) async throws {
        _ = try await perform(factory.pinMessage(broadcasterID: broadcasterID, moderatorID: moderatorID, messageID: messageID, durationSeconds: nil, token: token()))
    }

    func changeChatMode(broadcasterID: String, moderatorID: String, change: ChatModeChange) async throws {
        _ = try await perform(factory.updateChatSettings(broadcasterID: broadcasterID, moderatorID: moderatorID, change: change, token: token()))
    }

    func setShieldMode(broadcasterID: String, moderatorID: String, active: Bool) async throws {
        _ = try await perform(factory.shieldMode(broadcasterID: broadcasterID, moderatorID: moderatorID, active: active, token: token()))
    }

    func shieldModeActive(broadcasterID: String, moderatorID: String) async throws -> Bool? {
        let response = try await perform(factory.shieldModeStatus(broadcasterID: broadcasterID, moderatorID: moderatorID, token: token()))
        return StudioHelixDecoder.shieldModeActive(response.body)
    }

    private func token() async throws -> String {
        try await auth.validAccessToken()
    }

    private func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        let response = try await transport.send(request)
        guard response.isSuccess else {
            let error = APIError.from(status: response.status, rateLimitReset: response.rateLimit?.resetAt)
            MidgarLog.notice("Studio Helix \(request.url.path) \(response.status): \(error)", category: .studio)
            throw error
        }
        return response
    }
}
