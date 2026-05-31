import Foundation
import AuthenticationServices
import EmbrCore

@MainActor
final class TwitchLoginCoordinator: NSObject {
    private let anchor: ASPresentationAnchor
    private var session: ASWebAuthenticationSession?

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
        super.init()
    }

    func authorize(authorizeURL: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        continuation.resume(throwing: APIError.cancelled)
                    } else {
                        continuation.resume(throwing: APIError.network(String(describing: error)))
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: APIError.network("login returned no callback URL"))
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: APIError.network("could not start login session"))
            }
        }
    }

    nonisolated func code(from callbackURL: URL) -> String? {
        queryItem(named: "code", in: callbackURL)
    }

    nonisolated func state(from callbackURL: URL) -> String? {
        queryItem(named: "state", in: callbackURL)
    }

    private nonisolated func queryItem(named name: String, in url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return components.queryItems?.first(where: { $0.name == name })?.value
    }
}

extension TwitchLoginCoordinator: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { anchor }
    }
}
