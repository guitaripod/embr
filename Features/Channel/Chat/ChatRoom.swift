import Foundation
import EmbrCore
import MidgarCore

enum ChatRoomEvent: Sendable {
    case catalog(EmoteCatalog, BadgeCatalog)
    case messages([ChatMessage])
    case backfill([ChatMessage])
    case delete(messageID: String)
    case clearUser(userID: String)
    case clearChat
    case roomState(RoomState)
    case connection(ConnectionStatus)
    case notice(SystemNotice)
    case moderation(ModerationEvent)
}

actor ChatRoom {
    enum Mode: Sendable, Equatable {
        case live
        case vod(videoID: String)
    }

    private let channel: ChannelInfo
    private let mode: Mode
    private let loggedIn: Bool
    private let api: TwitchAPIProviding
    private let auth: AuthControlling
    private let emotes: EmoteCataloging
    private let recentMessages: RecentMessagesProviding
    /// Whether the room asks the recent-messages service for history, as Settings' Backfill Recent Messages says.
    private let backfills: Bool

    private let flushInterval: UInt64 = 200_000_000

    private var source: ChatSource?
    private var continuation: AsyncStream<ChatRoomEvent>.Continuation?
    private var consumeTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    /// A chat moving faster than anyone reads is drawn a little less often, in larger batches: the screen holds about a
    /// batch's worth of rows, so fewer, larger batches mean fewer rows laid out only to scroll straight past.
    private let busyFlushInterval: UInt64 = 320_000_000
    private static let busyBatch = 12
    private var lastBatchSize = 0
    private var setupTask: Task<Void, Never>?
    private var pending: [ChatMessage] = []
    private var pendingPlayback: TimeInterval?
    private var stopped = false
    private var gapBackfillTask: Task<Void, Never>?
    private var connectionPhase: ConnectionPhase = .initial

    private enum ConnectionPhase {
        case initial
        case connected
        case interrupted
    }

    private enum BackfillKind {
        case initial
        case gap
    }

    init(
        channel: ChannelInfo,
        mode: Mode = .live,
        loggedIn: Bool,
        api: TwitchAPIProviding,
        auth: AuthControlling,
        emotes: EmoteCataloging,
        recentMessages: RecentMessagesProviding,
        backfills: Bool = true
    ) {
        self.channel = channel
        self.mode = mode
        self.loggedIn = loggedIn
        self.api = api
        self.auth = auth
        self.emotes = emotes
        self.recentMessages = recentMessages
        self.backfills = backfills
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
        gapBackfillTask?.cancel()
        gapBackfillTask = nil
        setupTask = nil
        consumeTask = nil
        flushTask = nil
        await source?.stop()
        source = nil
        continuation?.finish()
        continuation = nil
    }

    func wake() async {
        guard !stopped else { return }
        await source?.wake()
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

    func deleteMessage(_ messageID: String) async throws {
        guard let user = await auth.currentUser() else { throw APIError.unauthorized }
        try await api.deleteMessage(broadcasterID: channel.id, moderatorID: user.id, messageID: messageID)
    }

    func banUser(userID: String, duration: Int?, reason: String?) async throws {
        guard let user = await auth.currentUser() else { throw APIError.unauthorized }
        try await api.banUser(broadcasterID: channel.id, moderatorID: user.id, userID: userID, duration: duration, reason: reason)
    }

    func unbanUser(userID: String) async throws {
        guard let user = await auth.currentUser() else { throw APIError.unauthorized }
        try await api.unbanUser(broadcasterID: channel.id, moderatorID: user.id, userID: userID)
    }

    var channelID: String { channel.id }

    /// Lets a message AutoMod held into chat, or keeps it out, as the signed-in moderator.
    func resolveHeldMessage(_ messageID: String, allow: Bool) async throws {
        guard let user = await auth.currentUser() else { throw APIError.unauthorized }
        try await api.resolveHeldMessage(moderatorID: user.id, messageID: messageID, allow: allow)
    }

    func resolveUnbanRequest(_ requestID: String, approve: Bool) async throws {
        guard let user = await auth.currentUser() else { throw APIError.unauthorized }
        try await api.resolveUnbanRequest(broadcasterID: channel.id, moderatorID: user.id, requestID: requestID, approve: approve, note: nil)
    }

    func lookupUser(login: String) async -> TwitchUser? {
        try? await api.user(login: login)
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
        if case .live = mode {
            await backfill(.initial)
            guard !stopped else { return }
        }
        startFlushing()
        consumeSource()
    }

    func setPlayback(seconds: TimeInterval) async {
        guard case .vod = mode else { return }
        if let source = source as? VODChatSource {
            await source.setPlayback(seconds: seconds)
        } else {
            pendingPlayback = seconds
        }
    }

    private func loadCatalog() async {
        _ = await emotes.loadGlobal()
        let channelLoad = await emotes.loadChannel(broadcasterID: channel.id, login: channel.broadcasterLogin)
        guard !stopped else { return }
        continuation?.yield(.catalog(channelLoad.emotes, channelLoad.badges))
    }

    private func backfill(_ kind: BackfillKind) async {
        guard backfills else { return }
        let recent = await recentMessages.recentMessages(channelLogin: channel.broadcasterLogin, limit: 100)
        guard !stopped, !Task.isCancelled, !recent.isEmpty else { return }
        let rewritten = recent.map(rewriteChannelID)
        switch kind {
        case .initial:
            continuation?.yield(.messages(rewritten))
        case .gap:
            MidgarLog.info("chat gap backfill: \(rewritten.count) candidates", category: .chat)
            continuation?.yield(.backfill(rewritten))
        }
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
        let source = makeSource()
        self.source = source
        if let pendingPlayback, let vod = source as? VODChatSource {
            self.pendingPlayback = nil
            Task { await vod.setPlayback(seconds: pendingPlayback) }
        }
        let stream = source.start()
        consumeTask = Task { [weak self] in
            for await event in stream {
                await self?.ingest(event)
            }
        }
    }

    private func makeSource() -> ChatSource {
        #if DEBUG
        if DemoWorld.isActive, case .live = mode { return DemoChatSource(channel: channel, moderates: DemoWorld.showsModeration) }
        #endif
        if case .vod(let videoID) = mode {
            return VODChatSource(channel: channel, videoID: videoID)
        }
        return loggedIn
            ? EventSubChatSource(channel: channel)
            : IRCChatSource(channel: channel)
    }

    private func ingest(_ event: ChatEvent) {
        switch event {
        case .message(let message):
            pending.append(message)
            scheduleFlush()
        case .deleteMessage(let messageID):
            flush()
            continuation?.yield(.delete(messageID: messageID))
        case .clearUserMessages(let userID, _):
            flush()
            continuation?.yield(.clearUser(userID: userID))
        case .clearChat:
            pending.removeAll()
            continuation?.yield(.clearChat)
        case .roomState(let state):
            continuation?.yield(.roomState(state))
        case .connection(let status):
            trackConnection(status)
            continuation?.yield(.connection(status))
        case .notice(let notice):
            MidgarLog.info("chat notice: \(notice.text)", category: .chat)
            continuation?.yield(.notice(notice))
        case .moderation(let event):
            continuation?.yield(.moderation(event))
        }
    }

    private func trackConnection(_ status: ConnectionStatus) {
        switch status {
        case .connected:
            if connectionPhase == .interrupted {
                scheduleGapBackfill()
            }
            connectionPhase = .connected
        case .disconnected, .reconnecting:
            if connectionPhase == .connected { connectionPhase = .interrupted }
        case .connecting, .idle:
            break
        }
    }

    private func scheduleGapBackfill() {
        gapBackfillTask?.cancel()
        gapBackfillTask = Task { [weak self] in
            await self?.backfill(.gap)
        }
    }

    private func startFlushing() {
        scheduleFlush()
    }

    /// Messages go up in batches at most every 200 ms, and the timer runs only while some are waiting, so a quiet chat
    /// does not wake the CPU five times a second.
    private func scheduleFlush() {
        guard flushTask == nil, !pending.isEmpty else { return }
        let interval = lastBatchSize > Self.busyBatch ? busyFlushInterval : flushInterval
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: interval)
            guard !Task.isCancelled else { return }
            await self?.finishScheduledFlush()
        }
    }

    private func finishScheduledFlush() {
        flushTask = nil
        flush()
    }

    /// Sends what is waiting now; a deletion or a cleared user follows the messages it may concern.
    private func flush() {
        guard !pending.isEmpty else { return }
        let batch = pending
        lastBatchSize = batch.count
        pending.removeAll(keepingCapacity: true)
        continuation?.yield(.messages(batch))
    }
}
