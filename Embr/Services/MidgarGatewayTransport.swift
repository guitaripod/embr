import Foundation
import EmbrCore
import MidgarCore

/// Carries the requests for Embr's worker through `MidgarCore.HTTP` to the `embr` route of the Midgar gateway, so
/// they carry `X-App-ID` and the client's retry and error rules. Callers keep `HTTPTransport`'s shape: a status
/// the worker or the gateway answered with comes back as an `HTTPResponse` and only a failure to get an answer
/// throws. Hosts other than the worker (Twitch, the emote services) keep using `URLSessionTransport`.
final class MidgarGatewayTransport: HTTPTransport {
    static let shared = MidgarGatewayTransport(client: EmbrMidgar.shared.worker)

    /// The `/v1/embr` route every worker request is mounted at.
    static let routeBaseURL = MidgarHTTPConfiguration.defaultBaseURL.appending(path: "v1/embr")

    private let client: MidgarHTTPClient
    private let routeBase: URL

    init(client: MidgarHTTPClient, routeBase: URL = MidgarGatewayTransport.routeBaseURL) {
        self.client = client
        self.routeBase = routeBase
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        #if DEBUG
        if DemoWorld.isActive { return DemoTransport.response(for: request) }
        #endif
        let gatewayRequest = try makeRequest(from: request)
        do {
            let (data, response) = try await client.sendRaw(gatewayRequest)
            return HTTPResponse(status: response.statusCode, headers: Self.headers(from: response), body: data)
        } catch {
            return try Self.response(for: error)
        }
    }

    /// Turns the worker URL into the gateway call: the service is `embr`, the path is what follows the route mount.
    func makeRequest(from request: HTTPRequest) throws -> MidgarRequest {
        guard let method = MidgarHTTPMethod(rawValue: request.method.rawValue),
              let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false),
              let path = Self.path(of: components.path, below: routeBase.path)
        else {
            throw APIError.invalidRequest("Not a request for the embr route: \(request.url.absoluteString)")
        }
        var headers = request.headers
        headers.removeValue(forKey: "Content-Type")
        return MidgarRequest(
            service: "embr",
            path: path,
            method: method,
            query: components.queryItems ?? [],
            headers: headers,
            body: try request.body.map(Self.body(from:))
        )
    }

    /// The part of `path` below `mount`, or nil when the path is not below it.
    private static func path(of path: String, below mount: String) -> String? {
        let mount = mount.hasSuffix("/") ? String(mount.dropLast()) : mount
        guard path == mount || path.hasPrefix(mount + "/") else { return nil }
        return String(path.dropFirst(mount.count))
    }

    /// The JSON the worker clients encode, re-wrapped as a value `MidgarRequest` can encode again.
    private static func body(from data: Data) throws -> JSONFragment {
        do {
            return try JSONDecoder().decode(JSONFragment.self, from: data)
        } catch {
            throw APIError.invalidRequest("The request body is not JSON.")
        }
    }

    private static func headers(from response: HTTPURLResponse) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String, let text = value as? String else { continue }
            result[name] = text
        }
        return result
    }

    /// An HTTP status the gateway client reports as an error is still an answer, so it returns as a response with that
    /// status; a failure to reach the gateway throws what `URLSessionTransport` would have thrown.
    private static func response(for error: Error) throws -> HTTPResponse {
        guard let error = error as? MidgarHTTPError else { throw APIError.network(error.localizedDescription) }
        switch error {
        case .unauthorized: return statusOnly(401)
        case .paymentRequired: return statusOnly(402)
        case .notFound: return statusOnly(404)
        case .rateLimited(let retryAfter, _): return rateLimited(retryAfter: retryAfter)
        case .server(let status, _, _): return statusOnly(status)
        case .timeout: throw APIError.timeout
        case .cancelled: throw APIError.cancelled
        case .offline, .decoding, .invalidRequest, .tokenUnavailable: throw APIError.network(error.localizedDescription)
        @unknown default: throw APIError.network(error.localizedDescription)
        }
    }

    private static func statusOnly(_ status: Int, headers: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(status: status, headers: headers, body: Data())
    }

    /// A 429 with the reset time EmbrCore reads from `RateLimit-Reset`, derived from the gateway's `Retry-After`.
    private static func rateLimited(retryAfter: TimeInterval?) -> HTTPResponse {
        guard let retryAfter else { return statusOnly(429) }
        let reset = Date().addingTimeInterval(retryAfter).timeIntervalSince1970
        return statusOnly(429, headers: ["ratelimit-reset": String(Int(reset))])
    }
}

/// Any JSON value. The worker clients encode their bodies in EmbrCore, which cannot depend on the gateway client's
/// `Encodable` request body, so the transport reads the bytes back into this and lets `MidgarHTTPClient` write them.
enum JSONFragment: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONFragment])
    case object([String: JSONFragment])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONFragment].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONFragment].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
