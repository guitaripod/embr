import Foundation

/// Builds the form-encoded POST every OAuth grant at `id.twitch.tv` takes, so the device flow, the client credentials
/// grant and the refresh grant share one encoder instead of three copies of the same escaping rules.
enum OAuthForm {
    static func post(_ url: URL, fields: [(String, String)]) -> HTTPRequest {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        let encoded = (components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        return HTTPRequest(
            method: .post,
            url: url,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: Data(encoded.utf8)
        )
    }
}
