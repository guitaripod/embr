import Foundation
import MidgarCore

/// A `URLProtocol` that answers every request of a session with a closure, and records what was sent. Each test
/// builds its own session, so tests that run in parallel never share a handler.
final class GatewayStub: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, [String: String], Data)

    /// The only shared state, keyed by a tag unique to each test's session.
    private static let handlers = LockedBox<[String: Handler]>([:])

    static func session(
        tag: String = UUID().uuidString,
        _ handler: @escaping Handler
    ) -> URLSession {
        handlers.value[tag] = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GatewayStub.self]
        configuration.httpAdditionalHeaders = ["X-Stub-Tag": tag]
        return URLSession(configuration: configuration)
    }

    static func client(_ handler: @escaping Handler) -> MidgarHTTPClient {
        MidgarHTTPClient(configuration: MidgarHTTPConfiguration(appID: "embr", session: session(handler)))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let tag = request.value(forHTTPHeaderField: "X-Stub-Tag") ?? ""
        guard let handler = Self.handlers.value[tag] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, headers, body) = try handler(request.withBody())
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLRequest {
    /// URLProtocol hands the body over as a stream; read it back so a handler can inspect it.
    fileprivate func withBody() -> URLRequest {
        guard httpBody == nil, let stream = httpBodyStream else { return self }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        var copy = self
        copy.httpBody = data
        return copy
    }
}
