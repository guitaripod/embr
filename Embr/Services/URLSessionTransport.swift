import Foundation
import EmbrCore

final class URLSessionTransport: HTTPTransport {
    static let shared = URLSessionTransport()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let urlRequest = Self.urlRequest(from: request)
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.network("Non-HTTP response")
            }
            return HTTPResponse(status: http.statusCode, headers: Self.headers(from: http), body: data)
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw Self.mapURLError(error)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    private static func urlRequest(from request: HTTPRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        return urlRequest
    }

    private static func headers(from response: HTTPURLResponse) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String, let stringValue = value as? String else { continue }
            result[name] = stringValue
        }
        return result
    }

    private static func mapURLError(_ error: URLError) -> APIError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return .network(error.localizedDescription)
        default:
            return .network(error.localizedDescription)
        }
    }
}
