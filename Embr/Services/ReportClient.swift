import Foundation
import EmbrCore

/// Submits user reports of chat messages to the Worker, which stores them for the
/// developer to review (App Store Guideline 1.2). Best-effort: a failure is logged
/// and never surfaced, because the reporter's local hide already removes the content.
final class ReportClient: Sendable {
    static let shared = ReportClient()

    private let transport: HTTPTransport
    private let endpoints: WorkerEndpoints
    private let logger = AppLogger.shared

    init(
        transport: HTTPTransport = URLSessionTransport.shared,
        endpoints: WorkerEndpoints = WorkerEndpoints(baseURL: Configuration.current.workerBaseURL)
    ) {
        self.transport = transport
        self.endpoints = endpoints
    }

    func submit(_ request: WorkerAPI.ReportRequest) async {
        do {
            _ = try await transport.send(endpoints.report(request))
            logger.info("submitted report for @\(request.authorLogin ?? "?") reason=\(request.reason)", category: .api)
        } catch {
            logger.warn("report submit failed: \(error)", category: .api)
        }
    }
}
