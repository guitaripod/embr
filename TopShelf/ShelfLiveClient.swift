import Foundation
import EmbrCore
import MidgarCore

/// The two requests the Top Shelf makes on its own: who is live among the person's channels (Helix, with an app
/// token from Embr's worker), and the preview playlists of the first few (the worker's playback route). Both go
/// through the Midgar gateway with `X-App-ID` like the app's own calls.
enum ShelfLiveClient {
    private static let gateway = MidgarHTTPClient(configuration: MidgarHTTPConfiguration(appID: "embr"))
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        return URLSession(configuration: configuration)
    }()

    /// The live streams among `userIDs`, or nil when Twitch or the worker could not be reached.
    static func liveStreams(userIDs: [String]) async -> [LiveStream]? {
        guard !userIDs.isEmpty else { return [] }
        do {
            let token = try await appToken()
            let request = HelixRequestFactory(clientID: Secrets.twitchClientID).streamsByUserIDs(userIDs, token: token)
            let (data, response) = try await session.data(for: urlRequest(request))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return try HelixDecoding.liveStreams(from: data)
        } catch {
            MidgarLog.notice("top shelf: live lookup failed: \(error)", category: MidgarLog.Category("topshelf"))
            return nil
        }
    }

    /// Preview playlist URLs by login, for those the worker could resolve in time.
    static func previews(logins: [String]) async -> [String: URL] {
        await withTaskGroup(of: (String, URL?).self) { group in
            for login in logins {
                group.addTask { (login, await preview(login: login)) }
            }
            var result: [String: URL] = [:]
            for await (login, url) in group {
                if let url { result[login] = url }
            }
            return result
        }
    }

    private static func preview(login: String) async -> URL? {
        let request = MidgarRequest(service: "embr", path: "/playback/\(login)")
        guard let (data, _) = try? await gateway.sendRaw(request),
              let playback = try? WorkerEndpoints.decodePlayback(data) else { return nil }
        return URL(string: playback.url)
    }

    private static func appToken() async throws -> String {
        let (data, _) = try await gateway.sendRaw(MidgarRequest(service: "embr", path: "/auth/app-token"))
        return try TwitchJSON.decode(AppToken.self, from: data).accessToken
    }

    private struct AppToken: Decodable {
        let accessToken: String
    }

    private static func urlRequest(_ request: HTTPRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        request.headers.forEach { urlRequest.setValue($0.value, forHTTPHeaderField: $0.key) }
        urlRequest.httpBody = request.body
        return urlRequest
    }
}
