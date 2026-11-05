import Foundation

/// The worker's side of the Founding Supporter badge: a supporter proves the purchase and the Twitch account it
/// belongs to, and every Embr viewer reads the list of supporters to draw the badge in chat.
public enum SupporterAPI {
    public static let productID = "com.guitaripod.embr.supporter"

    /// Sent once the purchase is verified on the device and the person is signed in with Twitch. The worker verifies
    /// the signed transaction with Apple's certificate chain and the token with Twitch, then ties the purchase to that
    /// Twitch user id; claiming again from another account moves the badge.
    public struct ClaimRequest: Codable, Sendable, Equatable {
        public let signedTransaction: String
        public let twitchAccessToken: String

        public init(signedTransaction: String, twitchAccessToken: String) {
            self.signedTransaction = signedTransaction
            self.twitchAccessToken = twitchAccessToken
        }
    }

    public struct ClaimResponse: Codable, Sendable, Equatable {
        public let twitchUserID: String

        public init(twitchUserID: String) {
            self.twitchUserID = twitchUserID
        }
    }

    public struct Directory: Codable, Sendable, Equatable {
        public let supporters: [String]

        public init(supporters: [String]) {
            self.supporters = supporters
        }
    }
}

extension WorkerEndpoints {
    public func supporters() -> HTTPRequest {
        HTTPRequest(method: .get, url: baseURL.appendingPathComponent("supporters"))
    }

    public func claimSupporter(_ body: SupporterAPI.ClaimRequest) -> HTTPRequest {
        HTTPRequest(
            method: .post,
            url: baseURL.appendingPathComponent("supporters/claim"),
            headers: ["Content-Type": "application/json"],
            body: try? TwitchJSON.encoder.encode(body)
        )
    }

    public static func decodeSupporterDirectory(_ data: Data) throws -> SupporterAPI.Directory {
        try TwitchJSON.decode(SupporterAPI.Directory.self, from: data)
    }

    public static func decodeSupporterClaim(_ data: Data) throws -> SupporterAPI.ClaimResponse {
        try TwitchJSON.decode(SupporterAPI.ClaimResponse.self, from: data)
    }
}
