import Foundation
import EmbrCore

enum EventSubCommands {
    static let specs: [CommandSpec] = [
        list,
        create,
        delete
    ]

    static let list = CommandSpec(
        ["eventsub", "list"],
        summary: "List EventSub subscriptions for the token's client.",
        examples: ["embr eventsub list --json"],
        scopes: ["any user or app token"]
    ) { _, context in
        let response = try await context.send(try listRequest(context))
        return CommandResult(try context.rawValue(response))
    }

    static let create = CommandSpec(
        ["eventsub", "create"],
        summary: "Create an EventSub WebSocket subscription.",
        positionals: [PositionalSpec("type", "Subscription type, e.g. channel.follow.")],
        options: [
            .value("session", "ID", "The WebSocket session id from a session_welcome.", required: true),
            .value("sub-version", "V", "Subscription version.", defaultValue: "1"),
            .repeated("condition", "KEY=VALUE", "Condition fields; repeat for each."),
            .flag("raw", "Print Twitch's response untouched (default).")
        ],
        examples: [
            "embr eventsub create channel.follow --session SESSION --condition broadcaster_user_id=123 --condition moderator_user_id=123"
        ],
        scopes: ["any user token"]
    ) { invocation, context in
        let type = try invocation.require(0, "subscription type")
        var condition: [String: String] = [:]
        for raw in invocation.list("condition") {
            let parts = raw.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty else {
                throw CLIError.usage("`--condition` takes key=value, got `\(raw)`.")
            }
            condition[parts[0]] = parts[1]
        }
        guard !condition.isEmpty else {
            throw CLIError.usage("Pass at least one --condition key=value.")
        }
        let subscription = EventSubSubscriptionRequest(
            type: type,
            version: invocation.value("sub-version") ?? "1",
            condition: condition,
            transport: EventSubSubscriptionRequest.Transport(sessionID: invocation.value("session") ?? "")
        )
        var request = try listRequest(context)
        request = HTTPRequest(
            method: .post,
            url: request.url,
            headers: request.headers.merging(["Content-Type": "application/json"]) { $1 },
            body: try subscription.encoded()
        )
        let response = try await context.send(request)
        return CommandResult(try context.rawValue(response))
    }

    static let delete = CommandSpec(
        ["eventsub", "delete"],
        summary: "Delete an EventSub subscription by id.",
        positionals: [PositionalSpec("id", "Subscription id.")],
        examples: ["embr eventsub delete 1234-5678"],
        scopes: ["any user or app token"],
        mutating: true
    ) { invocation, context in
        let id = try invocation.require(0, "subscription id")
        guard var components = URLComponents(string: "https://api.twitch.tv/helix/eventsub/subscriptions") else {
            throw CLIError(.internalError, "Could not build the EventSub URL.")
        }
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        let auth = try context.requireAuth()
        let request = HTTPRequest(
            method: .delete,
            url: components.url!,
            headers: [
                "Client-Id": auth.clientID,
                "Authorization": "Bearer \(auth.accessToken)"
            ]
        )
        let response = try await context.send(request)
        guard response.status == 204 else {
            throw CLIError.http(status: response.status, body: response.body)
        }
        return CommandResult(DeletedView(id: id, deleted: true))
    }

    private static func listRequest(_ context: RunContext) throws -> HTTPRequest {
        let auth = try context.requireAuth()
        guard var components = URLComponents(string: "https://api.twitch.tv/helix/eventsub/subscriptions") else {
            throw CLIError(.internalError, "Could not build the EventSub URL.")
        }
        if let after = context.options.after {
            components.queryItems = [URLQueryItem(name: "after", value: after)]
        }
        return HTTPRequest(
            method: .get,
            url: components.url!,
            headers: [
                "Client-Id": auth.clientID,
                "Authorization": "Bearer \(auth.accessToken)"
            ]
        )
    }
}

private struct DeletedView: Encodable {
    let id: String
    let deleted: Bool
}
