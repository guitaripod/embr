import Foundation

/// The worker's side of the Founding Supporter badge: a supporter proves the purchase and the Twitch account it
/// belongs to and picks the badge's look, and every Embr viewer reads the list of supporters to draw the badge, the
/// name style and the founding number.
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
        public let number: Int?
        public let color: String?
        public let nameStyle: String?

        public init(twitchUserID: String, number: Int? = nil, color: String? = nil, nameStyle: String? = nil) {
            self.twitchUserID = twitchUserID
            self.number = number
            self.color = color
            self.nameStyle = nameStyle
        }

        public var profile: Profile {
            Profile(number: number, color: color ?? Profile.defaultColor, nameStyle: nameStyle ?? NameStyle.twitch.rawValue)
        }
    }

    /// How other Embr viewers see a supporter's name.
    public enum NameStyle: String, Codable, Sendable, CaseIterable {
        /// The color the person picked on Twitch.
        case twitch
        /// The supporter's flame color.
        case color
        /// The flame color with a soft glow around the letters.
        case glow
    }

    /// What every Embr viewer knows about a supporter: the founding number and the look of the badge and the name.
    /// Color and style stay strings on the wire, so a value a newer worker adds never breaks an older app.
    public struct Profile: Codable, Sendable, Equatable {
        public static let defaultColor = "violet"

        public let number: Int?
        public let color: String
        public let nameStyle: String

        public init(number: Int?, color: String, nameStyle: String) {
            self.number = number
            self.color = color
            self.nameStyle = nameStyle
        }

        public var style: NameStyle {
            NameStyle(rawValue: nameStyle) ?? .twitch
        }
    }

    public struct Directory: Codable, Sendable, Equatable {
        public let supporters: [String]
        public let profiles: [String: Profile]?
        public let count: Int?

        public init(supporters: [String], profiles: [String: Profile]? = nil, count: Int? = nil) {
            self.supporters = supporters
            self.profiles = profiles
            self.count = count
        }

        /// Each supporter's profile; one the worker sent without a profile gets the default look and no number.
        public var resolvedProfiles: [String: Profile] {
            var resolved: [String: Profile] = [:]
            for id in supporters {
                resolved[id] = profiles?[id] ?? Profile(number: nil, color: Profile.defaultColor, nameStyle: NameStyle.twitch.rawValue)
            }
            return resolved
        }

        /// How many supporters there are, for the "join" line on the purchase screen.
        public var supporterCount: Int {
            count ?? supporters.count
        }
    }

    /// A supporter's choice of badge color and name style, proven with their Twitch token like the claim.
    public struct StyleRequest: Codable, Sendable, Equatable {
        public let twitchAccessToken: String
        public let color: String
        public let nameStyle: String

        public init(twitchAccessToken: String, color: String, nameStyle: NameStyle) {
            self.twitchAccessToken = twitchAccessToken
            self.color = color
            self.nameStyle = nameStyle.rawValue
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

    public func updateSupporterStyle(_ body: SupporterAPI.StyleRequest) -> HTTPRequest {
        HTTPRequest(
            method: .post,
            url: baseURL.appendingPathComponent("supporters/style"),
            headers: ["Content-Type": "application/json"],
            body: try? TwitchJSON.encoder.encode(body)
        )
    }

    public static func decodeSupporterProfile(_ data: Data) throws -> SupporterAPI.Profile {
        try TwitchJSON.decode(SupporterAPI.Profile.self, from: data)
    }

    public static func decodeSupporterDirectory(_ data: Data) throws -> SupporterAPI.Directory {
        try TwitchJSON.decode(SupporterAPI.Directory.self, from: data)
    }

    public static func decodeSupporterClaim(_ data: Data) throws -> SupporterAPI.ClaimResponse {
        try TwitchJSON.decode(SupporterAPI.ClaimResponse.self, from: data)
    }
}
