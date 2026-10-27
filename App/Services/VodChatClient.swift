import Foundation
import EmbrCore
import MidgarCore

protocol VodCommentsProviding: Sendable {
    func page(videoID: String, offset: Int) async throws -> VodCommentsPage
}

final class VodChatClient: VodCommentsProviding {
    static let shared = VodChatClient()

    private let transport: HTTPTransport
    private let endpoints: WorkerEndpoints

    init(
        transport: HTTPTransport = MidgarGatewayTransport.shared,
        endpoints: WorkerEndpoints = WorkerEndpoints(baseURL: Configuration.current.workerBaseURL)
    ) {
        self.transport = transport
        self.endpoints = endpoints
    }

    func page(videoID: String, offset: Int) async throws -> VodCommentsPage {
        let response = try await transport.send(endpoints.vodComments(id: videoID, offset: offset))
        guard response.isSuccess else {
            throw APIError.from(status: response.status, rateLimitReset: response.rateLimit?.resetAt)
        }
        return try WorkerEndpoints.decodeVodComments(response.body)
    }
}
