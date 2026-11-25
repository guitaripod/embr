import Foundation
import EmbrCore

enum PlaybackCommands {
    static let specs: [CommandSpec] = [url]

    static let url = CommandSpec(
        ["playback", "url"],
        summary: "Resolve a live or VOD HLS (Usher) URL without playing it.",
        details: """
        Uses Twitch's web playback token, the same public token the web player asks for. The URL is a
        master playlist; hand it to ffplay, mpv or the app. No account token is needed. The URL carries
        a signed token that expires, so resolve a fresh one for a later session.
        """,
        positionals: [PositionalSpec("channel", "Channel login for a live stream.", required: false)],
        options: [.value("vod", "ID", "Resolve this VOD id instead of a live channel.")],
        examples: [
            "embr playback url xqc",
            "embr playback url --vod 1234567890"
        ],
        needsAuth: false
    ) { invocation, context in
        let vod = invocation.value("vod")
        let channel = invocation.optional(0)
        guard vod != nil || channel != nil else {
            throw CLIError.usage("Pass a channel for live or --vod <id> for a VOD.")
        }
        if vod != nil, channel != nil {
            throw CLIError.usage("Pass either a channel or --vod, not both.")
        }
        let body = vod.map(GQLPlayback.vodRequestBody(vodID:)) ?? GQLPlayback.liveRequestBody(login: channel ?? "")
        let request = HTTPRequest(
            method: .post,
            url: URL(string: "https://gql.twitch.tv/gql")!,
            headers: [
                "Client-ID": GQLPlayback.webClientID,
                "Content-Type": "application/json"
            ],
            body: body
        )
        let response = try await context.send(request)
        let token: GQLPlayback.PlaybackAccessToken
        do {
            token = vod == nil
                ? try GQLPlayback.liveAccessToken(from: response.body)
                : try GQLPlayback.vodAccessToken(from: response.body)
        } catch {
            throw CLIError(.decode, "Twitch returned no playback token: \(error)")
        }
        let usher: URL
        if let vod {
            usher = GQLPlayback.usherVODURL(id: vod, token: token.value, signature: token.signature, clientID: GQLPlayback.webClientID)
        } else {
            usher = GQLPlayback.usherURL(login: channel ?? "", token: token.value, signature: token.signature, clientID: GQLPlayback.webClientID)
        }
        return CommandResult(
            PlaybackView(
                kind: vod == nil ? "live" : "vod",
                channel: channel,
                vod: vod,
                url: usher.absoluteString
            )
        )
    }
}

private struct PlaybackView: Encodable {
    let kind: String
    let channel: String?
    let vod: String?
    let url: String
}
