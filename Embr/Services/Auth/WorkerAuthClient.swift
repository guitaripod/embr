import Foundation
import EmbrCore

final class WorkerAuthClient: Sendable {
    static let shared = WorkerAuthClient()

    private let transport: HTTPTransport
    private let endpoints: WorkerEndpoints

    init(
        transport: HTTPTransport = URLSessionTransport.shared,
        endpoints: WorkerEndpoints = WorkerEndpoints(baseURL: Configuration.current.workerBaseURL)
    ) {
        self.transport = transport
        self.endpoints = endpoints
    }

    func loginURL(redirectURI: String, state: String) async throws -> URL {
        let response = try await send(endpoints.loginURL(redirectURI: redirectURI, state: state))
        let payload = try decode(LoginURLResponse.self, from: response.body)
        guard let url = URL(string: payload.url) else {
            throw APIError.decoding("login-url returned an invalid URL")
        }
        return url
    }

    func exchange(code: String, redirectURI: String) async throws -> WorkerAPI.TokenResponse {
        let response = try await send(endpoints.exchange(code: code, redirectURI: redirectURI))
        return try WorkerEndpoints.decodeToken(response.body)
    }

    func refresh(refreshToken: String) async throws -> WorkerAPI.TokenResponse {
        let response = try await send(endpoints.refresh(refreshToken: refreshToken))
        return try WorkerEndpoints.decodeToken(response.body)
    }

    func appToken() async throws -> (token: String, expiresIn: Int) {
        let response = try await send(endpoints.appToken())
        let payload = try decode(AppTokenResponse.self, from: response.body)
        return (payload.accessToken, payload.expiresIn)
    }

    func credentials(from token: WorkerAPI.TokenResponse) -> StoredCredentials {
        StoredCredentials(
            userID: token.userID ?? "",
            login: token.login ?? "",
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
            scopes: token.scope ?? []
        )
    }

    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let response = try await transport.send(request)
        guard response.isSuccess else {
            if let error = try? decode(WorkerAPI.ErrorResponse.self, from: response.body) {
                AppLogger.shared.warn("worker auth \(response.status): \(error.error)", category: .auth)
            }
            throw APIError.from(status: response.status, rateLimitReset: response.rateLimit?.resetAt)
        }
        return response
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try TwitchJSON.decode(type, from: data)
    }

    private struct LoginURLResponse: Decodable {
        let url: String
    }

    private struct AppTokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
    }
}
