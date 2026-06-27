import Foundation

public enum GQLPlayback {
    public static let webClientID = "kimne78kx3ncx6brgo4mv6wki5h1ko"

    public static let persistedQueryHash = "ed230aa1e33e07eebb8928504583da78a5173989fadfb1ac94be06a04f3cdbe9"

    public struct PlaybackAccessToken: Sendable, Equatable {
        public let value: String
        public let signature: String

        public init(value: String, signature: String) {
            self.value = value
            self.signature = signature
        }
    }

    public static func liveRequestBody(login: String) -> Data {
        requestBody(isLive: true, login: login, isVod: false, vodID: "")
    }

    public static func vodRequestBody(vodID: String) -> Data {
        requestBody(isLive: false, login: "", isVod: true, vodID: vodID)
    }

    public static func liveAccessToken(from data: Data) throws -> PlaybackAccessToken {
        let response = try TwitchJSON.decode(LiveResponse.self, from: data)
        guard let token = response.data.streamPlaybackAccessToken else {
            throw APIError.decoding("Missing streamPlaybackAccessToken")
        }
        return PlaybackAccessToken(value: token.value, signature: token.signature)
    }

    public static func vodAccessToken(from data: Data) throws -> PlaybackAccessToken {
        let response = try TwitchJSON.decode(VODResponse.self, from: data)
        guard let token = response.data.videoPlaybackAccessToken else {
            throw APIError.decoding("Missing videoPlaybackAccessToken")
        }
        return PlaybackAccessToken(value: token.value, signature: token.signature)
    }

    public static func usherURL(login: String, token: String, signature: String, clientID: String) -> URL {
        let base = "https://usher.ttvnw.net/api/channel/hls/\(login).m3u8"
        return buildUsherURL(base: base, token: token, signature: signature, clientID: clientID)
    }

    public static func usherVODURL(id: String, token: String, signature: String, clientID: String) -> URL {
        let base = "https://usher.ttvnw.net/vod/\(id).m3u8"
        return buildUsherURL(base: base, token: token, signature: signature, clientID: clientID)
    }

    private static func buildUsherURL(base: String, token: String, signature: String, clientID: String) -> URL {
        let url = QueryEncoder.url(
            base,
            items: [
                ("client_id", clientID),
                ("token", token),
                ("sig", signature),
                ("allow_source", "true"),
                ("allow_audio_only", "true"),
                ("playlist_include_framerate", "true"),
                ("player", "twitchweb")
            ]
        )
        guard let url else {
            return URL(string: base)!
        }
        return url
    }

    private static func requestBody(isLive: Bool, login: String, isVod: Bool, vodID: String) -> Data {
        let body = Request(
            operationName: "PlaybackAccessToken",
            variables: Variables(
                isLive: isLive,
                login: login,
                isVod: isVod,
                vodID: vodID,
                playerType: "site"
            ),
            extensions: Extensions(
                persistedQuery: PersistedQuery(version: 1, sha256Hash: persistedQueryHash)
            )
        )
        return (try? TwitchJSON.encoder.encode(body)) ?? Data()
    }

    private struct Request: Encodable {
        let operationName: String
        let variables: Variables
        let extensions: Extensions
    }

    private struct Variables: Encodable {
        let isLive: Bool
        let login: String
        let isVod: Bool
        let vodID: String
        let playerType: String
    }

    private struct Extensions: Encodable {
        let persistedQuery: PersistedQuery
    }

    private struct PersistedQuery: Encodable {
        let version: Int
        let sha256Hash: String
    }

    private struct TokenDTO: Decodable {
        let value: String
        let signature: String
    }

    private struct LiveResponse: Decodable {
        let data: LiveData

        struct LiveData: Decodable {
            let streamPlaybackAccessToken: TokenDTO?
        }
    }

    private struct VODResponse: Decodable {
        let data: VODData

        struct VODData: Decodable {
            let videoPlaybackAccessToken: TokenDTO?
        }
    }
}
