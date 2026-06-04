import Foundation
import EmbrCore

actor IRCChatSource: ChatSource {
    private let channel: ChannelInfo
    private let logger = AppLogger.shared

    private let endpoint = URL(string: "wss://irc-ws.chat.twitch.tv:443")!

    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var generation = 0
    private var continuation: AsyncStream<ChatEvent>.Continuation?
    private var buffer = ""
    private var roomState = RoomState()
    private var attempt = 0
    private var stopped = false

    init(channel: ChannelInfo) {
        self.channel = channel
    }

    nonisolated func start() -> AsyncStream<ChatEvent> {
        AsyncStream { continuation in
            Task { await self.begin(continuation) }
        }
    }

    func stop() async {
        stopped = true
        teardown()
        continuation?.yield(.connection(.disconnected(reason: nil)))
        continuation?.finish()
        continuation = nil
    }

    func send(_ text: String, replyParentID: String?) async throws -> SendResult {
        throw APIError.forbidden
    }

    private func begin(_ continuation: AsyncStream<ChatEvent>.Continuation) {
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stop() }
        }
        connect()
    }

    private func connect() {
        guard !stopped else { return }
        teardownSocket()
        buffer = ""
        roomState = RoomState()
        continuation?.yield(.connection(attempt == 0 ? .connecting : .reconnecting(attempt: attempt)))

        let session = self.session ?? URLSession(configuration: .default)
        self.session = session
        generation += 1
        let current = generation
        let task = session.webSocketTask(with: endpoint)
        socket = task
        task.resume()
        handshake()
        Task { [weak self] in
            await self?.receiveLoop(generation: current)
        }
    }

    private func handshake() {
        let nick = "justinfan\(Int.random(in: 10_000...99_999))"
        sendLine("CAP REQ :twitch.tv/tags twitch.tv/commands")
        sendLine("NICK \(nick)")
        sendLine("JOIN #\(channel.broadcasterLogin)")
    }

    private func sendLine(_ line: String) {
        socket?.send(.string(line + "\r\n")) { [weak self] error in
            guard let error else { return }
            Task { await self?.handleSendFailure(error) }
        }
    }

    private func handleSendFailure(_ error: Error) {
        guard !stopped else { return }
        logger.warn("IRC send failed: \(error)", category: .chat)
        scheduleReconnect()
    }

    private func receiveLoop(generation: Int) async {
        while !stopped {
            guard generation == self.generation, let task = socket else { return }
            do {
                let message = try await task.receive()
                let text: String
                switch message {
                case .string(let value): text = value
                case .data(let value): text = String(decoding: value, as: UTF8.self)
                @unknown default: continue
                }
                ingest(text, generation: generation)
            } catch {
                if stopped || Task.isCancelled { return }
                if generation == self.generation {
                    logger.warn("IRC receive failed: \(error)", category: .chat)
                    scheduleReconnect()
                }
                return
            }
        }
    }

    private func ingest(_ text: String, generation: Int) {
        guard generation == self.generation else { return }
        buffer += text
        while let range = buffer.range(of: "\r\n") {
            let line = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            if !line.isEmpty {
                process(line)
            }
        }
    }

    private func process(_ line: String) {
        guard let message = IRCMessage.parse(line) else { return }
        switch message.command.uppercased() {
        case "PING":
            let payload = message.parameters.first ?? "tmi.twitch.tv"
            sendLine("PONG :\(payload)")
        case "PRIVMSG", "USERNOTICE":
            if let chat = IRCMapper.chatMessage(from: message, channelID: channel.id) {
                continuation?.yield(.message(chat))
            }
        case "CLEARCHAT":
            if let targetUser = message.tags["target-user-id"], !targetUser.isEmpty {
                let login = message.parameters.last ?? ""
                continuation?.yield(.clearUserMessages(userID: targetUser, login: login))
            } else {
                continuation?.yield(.clearChat)
            }
        case "CLEARMSG":
            if let messageID = message.tags["target-msg-id"], !messageID.isEmpty {
                continuation?.yield(.deleteMessage(messageID: messageID))
            }
        case "ROOMSTATE":
            roomState = IRCMapper.roomState(from: message, merging: roomState)
            continuation?.yield(.roomState(roomState))
        case "NOTICE":
            emitNotice(from: message)
        case "RECONNECT":
            scheduleReconnect()
        case "366":
            onJoined()
        default:
            break
        }
    }

    private func emitNotice(from message: IRCMessage) {
        let text = message.parameters.last ?? ""
        guard !text.isEmpty else { return }
        let msgID = message.tags["msg-id"]
        continuation?.yield(.notice(SystemNotice(messageID: msgID, text: text, isError: Self.isErrorNotice(msgID))))
    }

    /// Twitch IRC `NOTICE` msg-id values that signal the channel can't be watched/chatted,
    /// so the guest preview should surface them as errors. Logged-out NOTICEs often omit the
    /// tag, so an absent or unknown id is treated as informational.
    private static func isErrorNotice(_ msgID: String?) -> Bool {
        guard let msgID else { return false }
        switch msgID {
        case "msg_channel_suspended", "msg_banned", "msg_timedout", "msg_rejected",
             "msg_rejected_mandatory", "msg_ratelimit", "msg_room_not_found",
             "msg_channel_blocked", "tos_ban", "msg_suspended", "msg_verified_email":
            return true
        default:
            return false
        }
    }

    private func onJoined() {
        guard !stopped else { return }
        attempt = 0
        continuation?.yield(.connection(.connected))
        logger.info("IRC joined #\(channel.broadcasterLogin)", category: .chat)
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        teardownSocket()
        attempt += 1
        let delay = Self.backoffSeconds(attempt: attempt)
        continuation?.yield(.connection(.reconnecting(attempt: attempt)))
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self?.connect()
        }
    }

    private func teardownSocket() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func teardown() {
        teardownSocket()
        session?.invalidateAndCancel()
        session = nil
    }

    private static func backoffSeconds(attempt: Int) -> Double {
        let capped = min(attempt, 4)
        let base = pow(2.0, Double(capped - 1))
        let jitter = Double.random(in: 0...0.5)
        return min(base, 8.0) + jitter
    }
}
