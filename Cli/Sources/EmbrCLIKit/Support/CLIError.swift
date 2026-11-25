import Foundation
import EmbrCore

public struct CLIError: Error, Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable {
        case usage
        case auth
        case notFound
        case rateLimited
        case network
        case server
        case decode
        case unavailable
        case internalError
    }

    public let kind: Kind
    public let message: String
    public let status: Int?
    public let hint: String?

    public init(_ kind: Kind, _ message: String, status: Int? = nil, hint: String? = nil) {
        self.kind = kind
        self.message = message
        self.status = status
        self.hint = hint
    }

    public var description: String { message }

    public var exitCode: Int32 {
        switch kind {
        case .usage: return 2
        case .auth: return 3
        case .notFound: return 4
        case .rateLimited: return 5
        case .network: return 6
        case .server: return 7
        case .decode: return 8
        case .unavailable, .internalError: return 1
        }
    }

    public static func usage(_ message: String, hint: String? = nil) -> CLIError {
        CLIError(.usage, message, hint: hint)
    }

    public static func auth(_ message: String, hint: String? = nil) -> CLIError {
        CLIError(.auth, message, hint: hint)
    }

    public static func notFound(_ message: String) -> CLIError {
        CLIError(.notFound, message)
    }

    public static func http(status: Int, body: Data) -> CLIError {
        let detail = APIErrorDetail.from(body)
        let message = detail?.message ?? "Twitch answered \(status)"
        switch status {
        case 401:
            return CLIError(.auth, message, status: status, hint: "Run `embr auth login` or set EMBR_ACCESS_TOKEN.")
        case 403:
            return CLIError(.auth, message, status: status, hint: detail?.hint ?? "The token is missing a scope this command needs.")
        case 404:
            return CLIError(.notFound, message, status: status)
        case 429:
            return CLIError(.rateLimited, message, status: status, hint: "Twitch's rate limit is exhausted; retry after the reset.")
        case 500..<600:
            return CLIError(.server, message, status: status)
        default:
            return CLIError(.server, message, status: status)
        }
    }
}

struct APIErrorDetail: Decodable, Sendable {
    let error: String?
    let status: Int?
    let message: String?

    static func from(_ data: Data) -> APIErrorDetail? {
        try? JSONDecoder().decode(APIErrorDetail.self, from: data)
    }

    var hint: String? {
        guard let error, !error.isEmpty else { return nil }
        return error.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct DryRun: Error {
    let request: HTTPRequest
}
