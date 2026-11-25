import Foundation
import EmbrCore
import WebSocketKit
import NIOPosix

enum StreamingCommands {
    static let specs: [CommandSpec] = [chatWatch, eventSubListen]

    static let chatWatch = CommandSpec(
        ["chat", "watch"],
        summary: "Stream a channel's chat as NDJSON.",
        details: """
        Signed in, this subscribes over EventSub and gets moderation events; without a token, or with
        --anonymous, it reads Twitch IRC anonymously. One JSON object per line: message, delete,
        clear, room state, notice. Use --limit or --duration for bounded runs.
        """,
        positionals: [PositionalSpec("channel", "Channel login.")],
        options: [
            .flag("anonymous", "Force the anonymous IRC transport."),
            .value("transport", "eventsub|irc", "Choose the transport explicitly."),
            .value("limit", "N", "Stop after this many events.", range: 1...1_000_000),
            .value("duration", "SECONDS", "Stop after this many seconds.", range: 1...86_400)
        ],
        examples: [
            "embr chat watch xqc --limit 50",
            "embr chat watch xqc --anonymous --json"
        ],
        needsAuth: false
    ) { invocation, context in
        let channel = try invocation.require(0, "channel").lowercased()
        let requested = invocation.value("transport")
        let anonymous = invocation.has("anonymous") || requested == "irc"
        let auth: AuthContext?
        if anonymous {
            auth = nil
        } else {
            auth = try? await context.authService.current()
        }
        if requested == "eventsub", auth == nil {
            throw CLIError.auth("EventSub needs a signed-in token.", hint: "Run `embr auth login` or drop --transport eventsub.")
        }
        let limit = invocation.int("limit")
        let duration = invocation.int("duration")

        if let auth, requested != "irc" {
            try await EventSubRunner(
                context: context,
                auth: auth,
                channel: channel,
                moderator: false,
                limit: limit,
                duration: duration
            ).run()
        } else {
            try await IRCRunner(
                context: context,
                channel: channel,
                limit: limit,
                duration: duration
            ).run()
        }
        return CommandResult(StreamDoneView(events: 0), silent: true)
    }

    static let eventSubListen = CommandSpec(
        ["eventsub", "listen"],
        summary: "Open an EventSub WebSocket and stream events as NDJSON.",
        details: """
        Prints the welcome, keepalives, notifications and reconnects. With --chat it subscribes the
        session to one channel's chat after the welcome; with --moderate it adds AutoMod, the
        moderation log and unban requests. Reconnects are followed automatically.
        """,
        options: [
            .value("chat", "CHANNEL", "Subscribe to this channel's chat."),
            .value("moderate", "CHANNEL", "Also subscribe as a moderator of this channel."),
            .value("limit", "N", "Stop after this many events.", range: 1...1_000_000),
            .value("duration", "SECONDS", "Stop after this many seconds.", range: 1...86_400)
        ],
        examples: [
            "embr eventsub listen --chat xqc --limit 20",
            "embr eventsub listen --duration 60 --json"
        ],
        scopes: ["user:read:chat"],
        needsAuth: true
    ) { invocation, context in
        let auth = try context.requireAuth()
        if let channel = invocation.value("chat") {
            try await EventSubRunner(
                context: context,
                auth: auth,
                channel: channel.lowercased(),
                moderator: invocation.value("moderate") != nil,
                limit: invocation.int("limit"),
                duration: invocation.int("duration")
            ).run()
        } else {
            try await RawEventSubRunner(
                context: context,
                auth: auth,
                chatChannel: nil,
                moderatorChannel: nil,
                limit: invocation.int("limit"),
                duration: invocation.int("duration")
            ).run()
        }
        return CommandResult(StreamDoneView(events: 0), silent: true)
    }
}

struct StreamDoneView: Encodable {
    let events: Int
}

private struct StreamLine: Encodable {
    let type: String
    let transport: String?
    let subscription: String?
    let channel: String?
    let data: JSONValue?
    let message: String?
}

private final class SocketBox: @unchecked Sendable {
    private let lock = NSLock()
    private var socket: WebSocket?
    private var client: WebSocketClient?

    func set(_ socket: WebSocket, _ client: WebSocketClient) {
        lock.lock()
        self.socket = socket
        self.client = client
        lock.unlock()
    }

    var current: WebSocket? {
        lock.lock()
        defer { lock.unlock() }
        return socket
    }

    func shutdown() {
        lock.lock()
        let client = self.client
        self.client = nil
        self.socket = nil
        lock.unlock()
        try? client?.syncShutdown()
    }

    deinit {
        lock.lock()
        let client = self.client
        self.client = nil
        lock.unlock()
        try? client?.syncShutdown()
    }
}

private struct Socket: Sendable {
    let box: SocketBox
    let stream: AsyncStream<String>

    static func connect(_ url: URL) async throws -> Socket {
        guard let scheme = url.scheme, let host = url.host else {
            throw CLIError(.network, "Invalid WebSocket URL: \(url.absoluteString)")
        }
        let client = WebSocketClient(eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton))
        let box = SocketBox()
        let (stream, continuation) = AsyncStream<String>.makeStream()
        do {
            try await withCheckedThrowingContinuation { (resume: CheckedContinuation<Void, Error>) in
                client.connect(
                    scheme: scheme,
                    host: host,
                    port: url.port ?? (scheme == "wss" ? 443 : 80),
                    path: url.path.isEmpty ? "/" : url.path,
                    query: url.query
                ) { socket in
                    box.set(socket, client)
                    socket.onText { _, text in continuation.yield(text) }
                    socket.onClose.whenComplete { _ in continuation.finish() }
                    resume.resume()
                }.whenFailure { error in
                    resume.resume(throwing: error)
                }
            }
        } catch {
            continuation.finish()
            box.shutdown()
            throw CLIError(.network, "WebSocket connection failed: \(error)")
        }
        return Socket(box: box, stream: stream)
    }

    func send(_ text: String) async throws {
        guard let socket = box.current else {
            throw CLIError(.network, "The WebSocket is closed.")
        }
        try await socket.send(text)
    }

    func close() async {
        if let socket = box.current {
            try? await socket.close()
        }
        box.shutdown()
    }
}

private final class EventSubRunner {
    private let context: RunContext
    private let auth: AuthContext
    private let channelLogin: String
    private let moderator: Bool
    private let limit: Int?
    private let duration: Int?
    private var emitted = 0

    init(context: RunContext, auth: AuthContext, channel: String, moderator: Bool, limit: Int?, duration: Int?) {
        self.context = context
        self.auth = auth
        channelLogin = channel
        self.moderator = moderator
        self.limit = limit
        self.duration = duration
    }

    func run() async throws {
        let broadcaster = try await resolveChannel(channelLogin)
        var url = URL(string: "wss://eventsub.wss.twitch.tv/ws?keepalive_timeout_seconds=30")!
        let deadline = duration.map { Date().addingTimeInterval(TimeInterval($0)) }
        var reconnects = 0

        while true {
            let socket = try await Socket.connect(url)
            let closer = startDeadlineTimer(socket, deadline: deadline)
            var nextURL: URL?
            var receivedWelcome = false

            for await text in socket.stream {
                if let deadline, Date() >= deadline { break }
                guard let data = text.data(using: .utf8) else { continue }
                let message: EventSubMessage
                do {
                    message = try EventSubMessage.decode(data)
                } catch {
                    continue
                }
                switch message {
                case .welcome(let sessionID, let keepalive):
                    receivedWelcome = true
                    try await subscribe(broadcasterID: broadcaster, sessionID: sessionID)
                    emit(StreamLine(
                        type: "welcome",
                        transport: "eventsub",
                        subscription: nil,
                        channel: channelLogin,
                        data: jsonValue(["session_id": sessionID, "keepalive_seconds": keepalive ?? 0]),
                        message: nil
                    ))
                case .keepalive:
                    emit(StreamLine(type: "keepalive", transport: "eventsub", subscription: nil, channel: channelLogin, data: nil, message: nil))
                case .notification(let type, let broadcasterID, let event):
                    var line = StreamLine(
                        type: "notification",
                        transport: "eventsub",
                        subscription: type,
                        channel: channelLogin,
                        data: (try? JSONValue.decode(event)) ?? .null,
                        message: nil
                    )
                    if let mapped = try? EventSubMapper.chatEvent(subscriptionType: type, eventData: event, timestamp: Date()) {
                        if case .message(let chat) = mapped {
                            line = StreamLine(
                                type: "message",
                                transport: "eventsub",
                                subscription: type,
                                channel: channelLogin,
                                data: line.data,
                                message: chat.plainText
                            )
                        }
                    }
                    _ = broadcasterID
                    emit(line)
                case .reconnect(let reconnect):
                    nextURL = URL(string: reconnect)
                    emit(StreamLine(type: "reconnect", transport: "eventsub", subscription: nil, channel: channelLogin, data: jsonValue(["url": reconnect]), message: nil))
                case .revocation(let reason, let type, _):
                    emit(StreamLine(type: "revocation", transport: "eventsub", subscription: type, channel: channelLogin, data: jsonValue(["reason": reason]), message: nil))
                }
                if let limit, emitted >= limit { break }
            }

            closer.cancel()
            await socket.close()
            if let limit, emitted >= limit { break }
            if let deadline, Date() >= deadline { break }
            guard receivedWelcome else {
                if let nextURL {
                    url = nextURL
                    reconnects += 1
                    if reconnects > 5 { break }
                    continue
                }
                break
            }
            guard let nextURL else { break }
            url = nextURL
            reconnects += 1
            if reconnects > 10 { break }
        }
    }

    private func subscribe(broadcasterID: String, sessionID: String) async throws {
        let userID: String
        if let known = auth.userID {
            userID = known
        } else {
            userID = try await context.authService.identity(auth).userID
        }
        var requests: [EventSubSubscriptionRequest] = [
            .chatMessage(broadcasterID: broadcasterID, userID: userID, sessionID: sessionID)
        ]
        requests += EventSubSubscriptionRequest.supplementalChatSubscriptions(
            broadcasterID: broadcasterID,
            userID: userID,
            sessionID: sessionID
        )
        if moderator {
            requests += EventSubSubscriptionRequest.moderatorSubscriptions(
                broadcasterID: broadcasterID,
                moderatorID: userID,
                sessionID: sessionID
            )
        }
        guard let primary = requests.first else { return }
        try await createSubscription(primary)
        for request in requests.dropFirst() {
            do {
                try await createSubscription(request)
            } catch {
                context.renderer.note("subscribe \(request.type) failed: \((error as? CLIError)?.message ?? String(describing: error))")
            }
        }
    }

    private func createSubscription(_ request: EventSubSubscriptionRequest) async throws {
        let body = try request.encoded()
        let http = HTTPRequest(
            method: .post,
            url: URL(string: "https://api.twitch.tv/helix/eventsub/subscriptions")!,
            headers: [
                "Client-Id": auth.clientID,
                "Authorization": "Bearer \(auth.accessToken)",
                "Content-Type": "application/json"
            ],
            body: body
        )
        let response = try await context.send(http)
        guard (200..<300).contains(response.status) else {
            throw CLIError.http(status: response.status, body: response.body)
        }
    }

    private func resolveChannel(_ login: String) async throws -> String {
        let resolver = Resolver(client: context.client, auth: auth)
        return try await resolver.userID(login)
    }

    private func emit(_ line: StreamLine) {
        emitted += 1
        context.renderer.writeLine(line)
    }

    private func startDeadlineTimer(_ socket: Socket, deadline: Date?) -> Task<Void, Never> {
        guard let deadline else { return Task {} }
        return Task {
            let seconds = deadline.timeIntervalSinceNow
            if seconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            await socket.close()
        }
    }

    private func jsonValue(_ object: [String: Any]) -> JSONValue? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONValue.decode(data)
    }
}

private final class RawEventSubRunner {
    private let context: RunContext
    private let auth: AuthContext
    private let chatChannel: String?
    private let moderatorChannel: String?
    private let limit: Int?
    private let duration: Int?
    private var emitted = 0

    init(context: RunContext, auth: AuthContext, chatChannel: String?, moderatorChannel: String?, limit: Int?, duration: Int?) {
        self.context = context
        self.auth = auth
        self.chatChannel = chatChannel
        self.moderatorChannel = moderatorChannel
        self.limit = limit
        self.duration = duration
    }

    func run() async throws {
        let channel = chatChannel ?? moderatorChannel
        let broadcasterID: String?
        if let channel {
            broadcasterID = try await Resolver(client: context.client, auth: auth).userID(channel)
        } else {
            broadcasterID = nil
        }
        var url = URL(string: "wss://eventsub.wss.twitch.tv/ws?keepalive_timeout_seconds=30")!
        let deadline = duration.map { Date().addingTimeInterval(TimeInterval($0)) }
        var reconnects = 0

        while true {
            let socket = try await Socket.connect(url)
            let closer = startDeadlineTimer(socket, deadline: deadline)
            var nextURL: URL?
            for await text in socket.stream {
                if let deadline, Date() >= deadline { break }
                guard let data = text.data(using: .utf8), let message = try? EventSubMessage.decode(data) else { continue }
                switch message {
                case .welcome(let sessionID, let keepalive):
                    if let channel, let broadcasterID {
                        try await subscribeChat(broadcasterID: broadcasterID, sessionID: sessionID, channel: channel)
                    }
                    emit(RawLine(type: "welcome", sessionID: sessionID, keepaliveSeconds: keepalive, subscription: nil, broadcasterID: nil, event: nil, url: nil, reason: nil))
                case .keepalive:
                    emit(RawLine(type: "keepalive", sessionID: nil, keepaliveSeconds: nil, subscription: nil, broadcasterID: nil, event: nil, url: nil, reason: nil))
                case .notification(let type, let broadcaster, let event):
                    let payload = (try? JSONValue.decode(event)) ?? .null
                    emit(RawLine(type: "notification", sessionID: nil, keepaliveSeconds: nil, subscription: type, broadcasterID: broadcaster, event: payload, url: nil, reason: nil))
                case .reconnect(let reconnect):
                    nextURL = URL(string: reconnect)
                    emit(RawLine(type: "reconnect", sessionID: nil, keepaliveSeconds: nil, subscription: nil, broadcasterID: nil, event: nil, url: reconnect, reason: nil))
                case .revocation(let reason, let type, _):
                    emit(RawLine(type: "revocation", sessionID: nil, keepaliveSeconds: nil, subscription: type, broadcasterID: nil, event: nil, url: nil, reason: reason))
                }
                if let limit, emitted >= limit { break }
            }
            closer.cancel()
            await socket.close()
            if let limit, emitted >= limit { break }
            if let deadline, Date() >= deadline { break }
            guard let nextURL else { break }
            url = nextURL
            reconnects += 1
            if reconnects > 10 { break }
        }
    }

    private func subscribeChat(broadcasterID: String, sessionID: String, channel: String) async throws {
        let userID: String
        if let known = auth.userID {
            userID = known
        } else {
            userID = try await context.authService.identity(auth).userID
        }
        var requests: [EventSubSubscriptionRequest] = [
            .chatMessage(broadcasterID: broadcasterID, userID: userID, sessionID: sessionID)
        ]
        requests += EventSubSubscriptionRequest.supplementalChatSubscriptions(broadcasterID: broadcasterID, userID: userID, sessionID: sessionID)
        if moderatorChannel != nil {
            requests += EventSubSubscriptionRequest.moderatorSubscriptions(broadcasterID: broadcasterID, moderatorID: userID, sessionID: sessionID)
        }
        guard let primary = requests.first else { return }
        try await createSubscription(primary)
        for request in requests.dropFirst() {
            do {
                try await createSubscription(request)
            } catch {
                context.renderer.note("subscribe \(request.type) failed: \((error as? CLIError)?.message ?? String(describing: error))")
            }
        }
    }

    private func createSubscription(_ request: EventSubSubscriptionRequest) async throws {
        let http = HTTPRequest(
            method: .post,
            url: URL(string: "https://api.twitch.tv/helix/eventsub/subscriptions")!,
            headers: [
                "Client-Id": auth.clientID,
                "Authorization": "Bearer \(auth.accessToken)",
                "Content-Type": "application/json"
            ],
            body: try request.encoded()
        )
        let response = try await context.send(http)
        guard (200..<300).contains(response.status) else {
            throw CLIError.http(status: response.status, body: response.body)
        }
    }

    private func emit(_ line: RawLine) {
        emitted += 1
        context.renderer.writeLine(line)
    }

    private func startDeadlineTimer(_ socket: Socket, deadline: Date?) -> Task<Void, Never> {
        guard let deadline else { return Task {} }
        return Task {
            let seconds = deadline.timeIntervalSinceNow
            if seconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            await socket.close()
        }
    }
}

private final class IRCRunner {
    private let context: RunContext
    private let channel: String
    private let limit: Int?
    private let duration: Int?
    private var emitted = 0

    init(context: RunContext, channel: String, limit: Int?, duration: Int?) {
        self.context = context
        self.channel = channel
        self.limit = limit
        self.duration = duration
    }

    func run() async throws {
        let url = URL(string: "wss://irc-ws.chat.twitch.tv:443")!
        let nickname = "justinfan\(Int.random(in: 10_000...99_999))"
        let deadline = duration.map { Date().addingTimeInterval(TimeInterval($0)) }

        while true {
            let socket = try await Socket.connect(url)
            let closer = startDeadlineTimer(socket, deadline: deadline)
            do {
                try await socket.send("CAP REQ :twitch.tv/tags twitch.tv/commands\r\n")
                try await socket.send("PASS SCHMOOPIIE\r\n")
                try await socket.send("NICK \(nickname)\r\n")
                try await socket.send("JOIN #\(channel)\r\n")
            } catch {
                closer.cancel()
                await socket.close()
                throw error
            }
            emit(StreamLine(type: "connected", transport: "irc", subscription: nil, channel: channel, data: nil, message: nil))

            for await text in socket.stream {
                if let deadline, Date() >= deadline { break }
                for raw in text.components(separatedBy: CharacterSet.newlines) where !raw.isEmpty {
                    let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !raw.isEmpty else { continue }
                    if raw.hasPrefix("PING") {
                        try? await socket.send("PONG :tmi.twitch.tv\r\n")
                        continue
                    }
                    if raw.contains(" RECONNECT") {
                        await socket.close()
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                        break
                    }
                    guard let message = IRCMessage.parse(raw) else { continue }
                    handle(message, raw: raw)
                }
                if let limit, emitted >= limit { break }
            }
            closer.cancel()
            await socket.close()
            if let limit, emitted >= limit { break }
            if let deadline, Date() >= deadline { break }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func handle(_ message: IRCMessage, raw: String) {
        switch message.command.uppercased() {
        case "PRIVMSG", "USERNOTICE":
            guard let chat = IRCMapper.chatMessage(from: message, channelID: channel) else { return }
            emit(StreamLine(
                type: "message",
                transport: "irc",
                subscription: nil,
                channel: channel,
                data: nil,
                message: chat.plainText
            ), extra: ["author": chat.author.login, "id": chat.id])
        case "ROOMSTATE":
            let state = IRCMapper.roomState(from: message, merging: RoomState())
            emit(StreamLine(type: "roomstate", transport: "irc", subscription: nil, channel: channel, data: nil, message: nil), extra: [
                "emote_only": state.emoteOnly ? "true" : "false",
                "followers_only": state.followersOnly.map(String.init) ?? "",
                "slow": state.slowMode.map(String.init) ?? ""
            ])
        case "CLEARCHAT":
            emit(StreamLine(type: "clear", transport: "irc", subscription: nil, channel: channel, data: nil, message: message.parameters.last))
        case "CLEARMSG":
            emit(StreamLine(type: "delete", transport: "irc", subscription: nil, channel: channel, data: nil, message: message.tags["target-msg-id"]))
        case "NOTICE":
            emit(StreamLine(type: "notice", transport: "irc", subscription: nil, channel: channel, data: nil, message: message.parameters.last))
        default:
            if context.options.raw {
                emit(StreamLine(type: "irc", transport: "irc", subscription: nil, channel: channel, data: nil, message: raw))
            }
        }
    }

    private func emit(_ line: StreamLine, extra: [String: String] = [:]) {
        var object: [String: Any] = [
            "type": line.type,
            "transport": line.transport ?? "irc",
            "channel": line.channel ?? channel
        ]
        if let message = line.message { object["message"] = message }
        for (key, value) in extra where !value.isEmpty {
            object[key] = value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let value = try? JSONValue.decode(data) else { return }
        emitted += 1
        context.renderer.writeLine(value)
    }

    private func startDeadlineTimer(_ socket: Socket, deadline: Date?) -> Task<Void, Never> {
        guard let deadline else { return Task {} }
        return Task {
            let seconds = deadline.timeIntervalSinceNow
            if seconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            await socket.close()
        }
    }
}

private struct RawLine: Encodable {
    let type: String
    let sessionID: String?
    let keepaliveSeconds: Int?
    let subscription: String?
    let broadcasterID: String?
    let event: JSONValue?
    let url: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case type
        case sessionID = "session_id"
        case keepaliveSeconds = "keepalive_seconds"
        case subscription
        case broadcasterID = "broadcaster_id"
        case event
        case url
        case reason
    }
}
