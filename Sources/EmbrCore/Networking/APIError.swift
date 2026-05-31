import Foundation

public enum APIError: Error, Sendable, Equatable {
    case invalidRequest(String)
    case network(String)
    case timeout
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(resetAt: Date?)
    case server(status: Int)
    case decoding(String)
    case unexpectedStatus(Int)
    case cancelled

    public static func from(status: Int, rateLimitReset: Date? = nil) -> APIError {
        switch status {
        case 400: return .invalidRequest("Bad request")
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 429: return .rateLimited(resetAt: rateLimitReset)
        case 500...599: return .server(status: status)
        default: return .unexpectedStatus(status)
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .timeout, .network, .rateLimited, .server:
            return true
        default:
            return false
        }
    }
}
