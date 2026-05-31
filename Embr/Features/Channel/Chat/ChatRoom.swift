import Foundation
import EmbrCore

enum ChatRoomEvent: Sendable {
    case catalog(EmoteCatalog, BadgeCatalog)
    case messages([ChatMessage])
    case delete(messageID: String)
    case clearUser(userID: String)
    case clearChat
    case roomState(RoomState)
    case connection(ConnectionStatus)
}

actor ChatRoom {
    private let channel: ChannelInfo
    private let loggedIn: Bool
    private let api: TwitchAPIProviding
    private let auth: AuthControlling
    private let emotes: EmoteCataloging
    private let recentMessages: RecentMessagesProviding
    private let logger = AppLogger.shared

    private let flushInterval: UInt64 = 200_000_000

    private var source: ChatSource?
    private var continuation: AsyncStream<ChatRoomEvent>.Continuation?
    private var consumeTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var setupTask: Task<Void, Never>?
    private var pending: [ChatMessage] = []
    private var stopped = false

    init(
        channel: ChannelInfo,
        loggedIn: Bool,
        api: TwitchAPIProviding,
        auth: AuthControlling,
        emotes: EmoteCataloging,
        recentMessages: RecentMessagesProviding
    ) {
        self.channel = channel
        self.loggedIn = loggedIn
        self.api = api
        self.auth = auth
        self.emotes = emotes
        self.recentMessages = recentMessages
    }

    nonisolated func start() -> AsyncStream<ChatRoomEvent> {
        AsyncStream { continuation in
            Task { await self.begin(continuation) }
        }
    }

    func stop() async {
        stopped = true
        setupTask?.cancel()
        consumeTask?.cancel()
        flushTask?.cancel()
        setupTask = nil
        consumeTask = nil
        flushTask = nil
        await source?.stop()
        source = nil
        continuation?.finish()
        continuation = nil
    }

    func send(_ text: String, replyParentID: String?) async throws -> SendResult {
        guard let user = await auth.currentUser() else {
            throw APIError.unauthorized
        }
        return try await api.sendMessage(
            broadcasterID: channel.id,
            senderID: user.id,
            text: text,
            replyParentMessageID: replyParentID
        )
    }

    private func begin(_ continuation: AsyncStream<ChatRoomEvent>.Continuation) {
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stop() }
        }
        setupTask = Task { [weak self] in
            await self?.setup()
        }
    }

    private func setup() async {
        await loadCatalog()
        guard !stopped else { return }
        await backfill()
        guard !stopped else { return }
        startFlushing()
        consumeSource()
    }

    private func loadCatalog() async {
        _ = await emotes.loadGlobal()
        let channelLoad = await emotes.loadChannel(broadcasterID: channel.id, login: channel.broadcasterLogin)
        guard !stopped else { return }
        continuation?.yield(.catalog(channelLoad.emotes, channelLoad.badges))
    }

    private func backfill() async {
        let recent = await recentMessages.recentMessages(channelLogin: channel.broadcasterLogin, limit: 100)
        guard !stopped, !recent.isEmpty else { return }
        let rewritten = recent.map(rewriteChannelID)
        continuation?.yield(.messages(rewritten))
    }

    private func rewriteChannelID(_ message: ChatMessage) -> ChatMessage {
        guard message.channelID != channel.id else { return message }
        return ChatMessage(
            id: message.id,
            channelID: channel.id,
            timestamp: message.timestamp,
            author: message.author,
            fragments: message.fragments,
            badges: message.badges,
            messageType: message.messageType,
            isAction: message.isAction,
            bits: message.bits,
            reply: message.reply,
            notice: message.notice,
            sharedChatSource: message.sharedChatSource,
            moderation: message.moderation
        )
    }

    private func consumeSource() {
        let source: ChatSource = loggedIn
            ? EventSubChatSource(channel: channel, api: api, auth: auth)
            : IRCChatSource(channel: channel)
        self.source = source
        let stream = source.start()
        consumeTask = Task { [weak self] in
            for await event in stream {
                await self?.ingest(event)
            }
        }
    }

    private func ingest(_ event: ChatEvent) {
        switch event {
        case .message(let message):
            pending.append(message)
        case .deleteMessage(let messageID):
            continuation?.yield(.delete(messageID: messageID))
        case .clearUserMessages(let userID, _):
            continuation?.yield(.clearUser(userID: userID))
        case .clearChat:
            continuation?.yield(.clearChat)
        case .roomState(let state):
            continuation?.yield(.roomState(state))
        case .connection(let status):
            continuation?.yield(.connection(status))
        case .notice(let notice):
            logger.info("chat notice: \(notice.text)", category: .chat)
        }
    }

    private func startFlushing() {
        let interval = flushInterval
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { return }
                await self?.flush()
            }
        }
    }

    private func flush() {
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        continuation?.yield(.messages(batch))
    }
}
