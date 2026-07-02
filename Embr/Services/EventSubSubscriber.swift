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

    func createChatSubscriptions(broadcasterID: String, userID: String, sessionID: String, token: String) async throws {
        try await create(
            .chatMessage(broadcasterID: broadcasterID, userID: userID, sessionID: sessionID),
            token: token
        )
        let supplemental = EventSubSubscriptionRequest.supplementalChatSubscriptions(
            broadcasterID: broadcasterID,
            userID: userID,
            sessionID: sessionID
        )
        await withTaskGroup(of: Void.self) { group in
            for request in supplemental {
                group.addTask {
                    do {
                        try await self.create(request, token: token)
                    } catch {
                        self.logger.warn("EventSub optional subscribe \(request.type) failed: \(error)", category: .eventsub)
                    }
                }
            }
        }
    }

    private func create(_ subscription: EventSubSubscriptionRequest, token: String) async throws {
        let body = try subscription.encoded()
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
            logger.error("EventSub subscribe \(subscription.type) \(response.status): \(error)", category: .eventsub)
            throw error
        }
    }
}
