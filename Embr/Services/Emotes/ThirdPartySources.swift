import Foundation
import EmbrCore

final class SevenTVSource: ThirdPartyEmoteSource {
    let provider: EmoteProvider = .sevenTV
    private let transport: HTTPTransport

    init(transport: HTTPTransport = URLSessionTransport.shared) {
        self.transport = transport
    }

    func globalEmotes() async throws -> [Emote] {
        await fetch(url: "https://7tv.io/v3/emote-sets/global") { try SevenTVDTO.emotes(fromGlobal: $0) }
    }

    func channelEmotes(twitchUserID: String) async throws -> [Emote] {
        await fetch(url: "https://7tv.io/v3/users/twitch/\(twitchUserID)") { try SevenTVDTO.emotes(fromUser: $0).emotes }
    }

    private func fetch(url: String, parse: @Sendable (Data) throws -> [Emote]) async -> [Emote] {
        guard let url = URL(string: url) else { return [] }
        do {
            let response = try await transport.send(HTTPRequest(method: .get, url: url))
            guard response.isSuccess else { return [] }
            return try parse(response.body)
        } catch {
            AppLogger.shared.warn("7TV fetch failed: \(error)", category: .emote)
            return []
        }
    }
}

final class BetterTTVSource: ThirdPartyEmoteSource {
    let provider: EmoteProvider = .betterTTV
    private let transport: HTTPTransport

    init(transport: HTTPTransport = URLSessionTransport.shared) {
        self.transport = transport
    }

    func globalEmotes() async throws -> [Emote] {
        await fetch(url: "https://api.betterttv.net/3/cached/emotes/global") { try BetterTTVDTO.globalEmotes($0) }
    }

    func channelEmotes(twitchUserID: String) async throws -> [Emote] {
        await fetch(url: "https://api.betterttv.net/3/cached/users/twitch/\(twitchUserID)") { try BetterTTVDTO.channelEmotes($0) }
    }

    private func fetch(url: String, parse: @Sendable (Data) throws -> [Emote]) async -> [Emote] {
        guard let url = URL(string: url) else { return [] }
        do {
            let response = try await transport.send(HTTPRequest(method: .get, url: url))
            guard response.isSuccess else { return [] }
            return try parse(response.body)
        } catch {
            AppLogger.shared.warn("BetterTTV fetch failed: \(error)", category: .emote)
            return []
        }
    }
}

final class FrankerFaceZSource: ThirdPartyEmoteSource {
    let provider: EmoteProvider = .frankerFaceZ
    private let transport: HTTPTransport

    init(transport: HTTPTransport = URLSessionTransport.shared) {
        self.transport = transport
    }

    func globalEmotes() async throws -> [Emote] {
        await fetch(url: "https://api.frankerfacez.com/v1/set/global") { try FrankerFaceZDTO.globalEmotes($0) }
    }

    func channelEmotes(twitchUserID: String) async throws -> [Emote] {
        await fetch(url: "https://api.frankerfacez.com/v1/room/id/\(twitchUserID)") { try FrankerFaceZDTO.roomEmotes($0) }
    }

    private func fetch(url: String, parse: @Sendable (Data) throws -> [Emote]) async -> [Emote] {
        guard let url = URL(string: url) else { return [] }
        do {
            let response = try await transport.send(HTTPRequest(method: .get, url: url))
            guard response.isSuccess else { return [] }
            return try parse(response.body)
        } catch {
            AppLogger.shared.warn("FrankerFaceZ fetch failed: \(error)", category: .emote)
            return []
        }
    }
}
