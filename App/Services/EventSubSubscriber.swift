import Foundation
import EmbrCore
import MidgarCore

final class EventSubSubscriber: Sendable {
    static let shared = EventSubSubscriber()

    private let transport: HTTPTransport
    private let clientID: String
    private let endpoint: URL

    init(
        transport: HTTPTransport = URLSessionTransport.shared,
        clientID: String = Configuration.current.twitchClientID,
        endpoint: URL = URL(string: "https://api.twitch.tv/helix/eventsub/subscriptions")!
    ) {
        self.transport = transport
        self.clientID = clientID
        self.endpoint = endpoint
    }

    /// Subscribes the session to one channel's chat and returns the ids of the subscriptions made, so they can be
    /// deleted when the channel's chat closes while the session stays open. The message subscription must succeed;
    /// the others (notifications, deletions, clears) are best effort.
    func createChatSubscriptions(broadcasterID: String, userID: String, sessionID: String, token: String) async throws -> [String] {
        var ids = try await create(
            .chatMessage(broadcasterID: broadcasterID, userID: userID, sessionID: sessionID),
            token: token
        ).map { [$0] } ?? []
        let supplemental = EventSubSubscriptionRequest.supplementalChatSubscriptions(
            broadcasterID: broadcasterID,
            userID: userID,
            sessionID: sessionID
        )
        await withTaskGroup(of: String?.self) { group in
            for request in supplemental {
                group.addTask {
                    do {
                        return try await self.create(request, token: token)
                    } catch {
                        MidgarLog.notice("EventSub optional subscribe \(request.type) failed: \(error)", category: .eventsub)
                        return nil
                    }
                }
            }
            for await id in group {
                if let id { ids.append(id) }
            }
        }
        return ids
    }

    /// Deletes subscriptions the session no longer needs. Failures are only logged: Twitch drops a session's
    /// subscriptions itself when the session closes.
    func deleteSubscriptions(_ ids: [String], token: String) async {
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { await self.delete(id, token: token) }
            }
        }
    }

    private func delete(_ id: String, token: String) async {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        guard let url = components.url else { return }
        let request = HTTPRequest(method: .delete, url: url, headers: ["Client-Id": clientID, "Authorization": "Bearer \(token)"])
        do {
            let response = try await transport.send(request)
            if !response.isSuccess {
                MidgarLog.notice("EventSub unsubscribe \(id) \(response.status)", category: .eventsub)
            }
        } catch {
            MidgarLog.notice("EventSub unsubscribe \(id) failed: \(error)", category: .eventsub)
        }
    }

    private func create(_ subscription: EventSubSubscriptionRequest, token: String) async throws -> String? {
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
            MidgarLog.error("EventSub subscribe \(subscription.type) \(response.status): \(error)", category: .eventsub)
            throw error
        }
        return Self.subscriptionID(in: response.body)
    }

    private static func subscriptionID(in body: Data) -> String? {
        let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        let first = (root?["data"] as? [[String: Any]])?.first
        return first?["id"] as? String
    }
}
