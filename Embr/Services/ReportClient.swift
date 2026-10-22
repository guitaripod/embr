import Foundation
import EmbrCore
import MidgarCore

/// Submits user reports of chat messages to the Worker, which stores them for the
/// developer to review (App Store Guideline 1.2). Best-effort: a failure is logged
/// and never surfaced, because the reporter's local hide already removes the content.
final class ReportClient: Sendable {
    static let shared = ReportClient()

    private let transport: HTTPTransport
    private let endpoints: WorkerEndpoints

    init(
        transport: HTTPTransport = MidgarGatewayTransport.shared,
        endpoints: WorkerEndpoints = WorkerEndpoints(baseURL: Configuration.current.workerBaseURL)
    ) {
        self.transport = transport
        self.endpoints = endpoints
    }

    func submit(_ request: WorkerAPI.ReportRequest) async {
        do {
            _ = try await transport.send(endpoints.report(request))
            MidgarLog.info("submitted report for @\(request.authorLogin ?? "?") reason=\(request.reason)", category: .api)
        } catch {
            MidgarLog.notice("report submit failed: \(error)", category: .api)
        }
    }
}
