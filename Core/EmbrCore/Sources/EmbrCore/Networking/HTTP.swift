import Foundation

public enum HTTPMethod: String, Sendable, Equatable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

public struct HTTPRequest: Sendable, Equatable {
    public var method: HTTPMethod
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: HTTPMethod = .get, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }

    public mutating func setHeader(_ name: String, _ value: String) {
        headers[name] = value
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public var isSuccess: Bool { (200..<300).contains(status) }

    public var rateLimit: RateLimit? {
        RateLimit(headers: headers)
    }

    public func header(_ name: String) -> String? {
        if let exact = headers[name] { return exact }
        let lowered = name.lowercased()
        return headers.first(where: { $0.key.lowercased() == lowered })?.value
    }
}

public struct RateLimit: Sendable, Equatable {
    public let limit: Int?
    public let remaining: Int?
    public let resetAt: Date?

    public init?(headers: [String: String]) {
        func value(_ key: String) -> String? {
            headers.first(where: { $0.key.lowercased() == key })?.value
        }
        let limitValue = value("ratelimit-limit").flatMap(Int.init)
        let remainingValue = value("ratelimit-remaining").flatMap(Int.init)
        let resetValue = value("ratelimit-reset").flatMap(TimeInterval.init)
        if limitValue == nil && remainingValue == nil && resetValue == nil { return nil }
        self.limit = limitValue
        self.remaining = remainingValue
        self.resetAt = resetValue.map { Date(timeIntervalSince1970: $0) }
    }

    public init(limit: Int?, remaining: Int?, resetAt: Date?) {
        self.limit = limit
        self.remaining = remaining
        self.resetAt = resetAt
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public enum QueryEncoder {
    public static func url(_ base: String, items: [(String, String?)]) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        let queryItems = items.compactMap { name, value -> URLQueryItem? in
            guard let value else { return nil }
            return URLQueryItem(name: name, value: value)
        }
        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }
        return components.url
    }
}
