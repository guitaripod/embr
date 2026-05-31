import Foundation
import EmbrCore

final class RecentMessagesClient: RecentMessagesProviding {
    static let shared = RecentMessagesClient()

    private let transport: HTTPTransport
    private let baseURL: URL
    private let logger = AppLogger.shared

    init(
        transport: HTTPTransport = URLSessionTransport.shared,
        baseURL: URL = Configuration.current.recentMessagesBaseURL
    ) {
        self.transport = transport
        self.baseURL = baseURL
    }

    /// The robotty recent-messages API keys responses by channel login, and the parsed
    /// `ChatMessage` values carry no broadcaster id, so the login is used as the `channelID`
    /// placeholder. Callers that need the real broadcaster id rewrite it after backfill.
    func recentMessages(channelLogin: String, limit: Int) async -> [ChatMessage] {
        guard let url = url(channelLogin: channelLogin, limit: limit) else { return [] }
        do {
            let response = try await transport.send(HTTPRequest(method: .get, url: url))
            guard response.isSuccess else { return [] }
            return RecentMessagesParser.messages(fromJSON: response.body, channelID: channelLogin)
        } catch {
            logger.warn("Recent messages fetch failed for \(channelLogin): \(error)", category: .chat)
            return []
        }
    }

    private func url(channelLogin: String, limit: Int) -> URL? {
        QueryEncoder.url(
            baseURL.appendingPathComponent("recent-messages").appendingPathComponent(channelLogin).absoluteString,
            items: [("limit", String(limit))]
        )
    }
}
