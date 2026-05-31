import Foundation
import EmbrCore

final class EventSubSubscriber: Sendable {
    static let shared = EventSubSubscriber()

    private let transport: HTTPTransport
    private let clientID: String
    private let endpoint: URL
    private let logger = AppLogger.shared

    init(
        transport: HTTPTransport = URLSessionTransport.shared,
        clientID: String = Configuration.current.twitchClientID,
        endpoint: URL = URL(string: "https://api.twitch.tv/helix/eventsub/subscriptions")!
    ) {
        self.transport = transport
        self.clientID = clientID
        self.endpoint = endpoint
    }

    func createChatSubscription(broadcasterID: String, userID: String, sessionID: String, token: String) async throws {
        let body = try EventSubSubscriptionRequest
            .chatMessage(broadcasterID: broadcasterID, userID: userID, sessionID: sessionID)
            .encoded()
        let request = HTTPRequest(
            method: .post,
            url: endpoint,
            headers: [
                "Client-Id": clientID,
                "Authorization": "Bearer \(token)",
                "Content-Type": "application/json"
            ],
            body: body
        )
        let response = try await transport.send(request)
        guard response.isSuccess else {
            let error = APIError.from(status: response.status, rateLimitReset: response.rateLimit?.resetAt)
            logger.error("EventSub subscribe \(response.status): \(error)", category: .eventsub)
            throw error
        }
    }
}
