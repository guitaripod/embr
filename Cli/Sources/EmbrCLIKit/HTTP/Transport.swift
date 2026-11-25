import Foundation
import EmbrCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 20) {
        self.timeout = timeout
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = max(timeout * 3, 60)
        configuration.httpAdditionalHeaders = ["User-Agent": "embr-cli/\(EmbrCLIVersion.version)"]
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.timeoutInterval = timeout
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.httpBody = request.body

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw CLIError(.network, "Twitch returned a non-HTTP response.")
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                headers[String(describing: key)] = String(describing: value)
            }
            return HTTPResponse(status: http.statusCode, headers: headers, body: data)
        } catch let error as CLIError {
            throw error
        } catch {
            throw CLIError(.network, "Request failed: \(error.localizedDescription)")
        }
    }
}

public final class APIClient: @unchecked Sendable {
    private let transport: HTTPTransport
    private let retries: Int
    private let dryRun: Bool
    private let verbose: Bool
    private let trace: Bool
    private let log: @Sendable (String) -> Void

    public init(
        transport: HTTPTransport,
        retries: Int = 2,
        dryRun: Bool = false,
        verbose: Bool = false,
        trace: Bool = false,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.transport = transport
        self.retries = max(0, retries)
        self.dryRun = dryRun
        self.verbose = verbose
        self.trace = trace
        self.log = log
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if dryRun {
            throw DryRun(request: request)
        }
        var attempt = 0
        while true {
            let started = Date()
            do {
                let response = try await transport.send(request)
                if verbose || trace {
                    log("\(request.method.rawValue) \(redactedURL(request.url)) \(response.status) \(elapsed(since: started))")
                }
                if trace, let remaining = response.header("Ratelimit-Remaining") {
                    log("ratelimit remaining \(remaining)")
                }
                if shouldRetry(response: response, request: request, attempt: attempt) {
                    try await sleepBeforeRetry(response: response, attempt: attempt)
                    attempt += 1
                    continue
                }
                return response
            } catch let error as CLIError {
                if error.kind == .network, request.method == .get, attempt < retries {
                    try await Task.sleep(nanoseconds: backoff(attempt))
                    attempt += 1
                    continue
                }
                throw error
            }
        }
    }

    public func requireSuccess(_ response: HTTPResponse) throws {
        guard (200..<300).contains(response.status) else {
            throw CLIError.http(status: response.status, body: response.body)
        }
    }

    public func decode<T: Decodable>(_ type: T.Type, from response: HTTPResponse) throws -> T {
        try requireSuccess(response)
        do {
            return try TwitchJSON.decoder.decode(type, from: response.body)
        } catch {
            throw CLIError(.decode, "Could not decode \(type): \(error)")
        }
    }

    public func sleepIfExhausted(_ response: HTTPResponse) async {
        guard let remaining = response.header("Ratelimit-Remaining"), Int(remaining) == 0 else { return }
        guard let reset = resetDate(response) else { return }
        let seconds = reset.timeIntervalSinceNow
        guard seconds > 0, seconds < 900 else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func shouldRetry(response: HTTPResponse, request: HTTPRequest, attempt: Int) -> Bool {
        guard request.method == .get, attempt < retries else { return false }
        return [429, 502, 503, 504].contains(response.status)
    }

    private func sleepBeforeRetry(response: HTTPResponse, attempt: Int) async throws {
        if let retryAfter = response.header("Retry-After"), let seconds = Double(retryAfter) {
            try await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
            return
        }
        if let reset = resetDate(response) {
            let seconds = min(max(reset.timeIntervalSinceNow, 0), 60)
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000) + backoff(attempt))
            return
        }
        try await Task.sleep(nanoseconds: backoff(attempt))
    }

    private func resetDate(_ response: HTTPResponse) -> Date? {
        guard let raw = response.header("Ratelimit-Reset"), let seconds = Double(raw) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private func backoff(_ attempt: Int) -> UInt64 {
        UInt64(min(pow(2.0, Double(attempt)) * 250_000_000, 4_000_000_000))
    }

    private func elapsed(since start: Date) -> String {
        "\(Int(Date().timeIntervalSince(start) * 1000))ms"
    }

    private func redactedURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        components.queryItems = components.queryItems?.map { item in
            ["token", "secret", "code"].contains(item.name.lowercased())
                ? URLQueryItem(name: item.name, value: "REDACTED")
                : item
        }
        return components.url?.absoluteString ?? url.absoluteString
    }
}
