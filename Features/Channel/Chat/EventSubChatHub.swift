import Foundation
import EmbrCore
import MidgarCore

/// One EventSub WebSocket for every chat the signed-in viewer has open. Twitch allows a user three WebSocket
/// connections with subscriptions, so chats share this one: a channel's subscriptions are made on the shared session
/// when its first listener joins, its events go to that channel's listeners only, and its subscriptions are deleted
/// when the last listener leaves. The socket closes a little after the last chat does.
actor EventSubChatHub {
    static let shared = EventSubChatHub()

    private struct Room {
        let channel: ChannelInfo
        var listeners: [UUID: AsyncStream<ChatEvent>.Continuation] = [:]
        var subscriptionIDs: [String] = []
        var moderationIDs: [String] = []
        var subscribed = false
        var subscribeTask: Task<Void, Never>?
        var attempt = 0

        func send(_ event: ChatEvent) {
            for listener in listeners.values { listener.yield(event) }
        }
    }

    private let auth: AuthControlling
    private let subscriber: EventSubSubscriber
    private let endpoint = URL(string: "wss://eventsub.wss.twitch.tv/ws?keepalive_timeout_seconds=30")!
    private let defaultKeepalive = 30
    private let idleClose: Double = 20

    private let socketClient = ChatSocketClient()
    private var sockets: [Int: ChatSocket] = [:]
    private var liveGeneration = 0
    private var nextGeneration = 0
    private var rooms: [String: Room] = [:]
    private var sessionID: String?
    private var sessionUserID: String?
    private var keepaliveSeconds: Int
    private var lastKeepalive = Date()
    private var attempt = 0
    private var gaveUp = false
    private var watchdogTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?

    init(auth: AuthControlling = AuthService.shared, subscriber: EventSubSubscriber = .shared) {
        self.auth = auth
        self.subscriber = subscriber
        self.keepaliveSeconds = defaultKeepalive
    }

    /// The channel's chat events for one listener, until it calls ``leave(channelID:listener:)`` or stops iterating.
    nonisolated func join(_ channel: ChannelInfo, listener: UUID) -> AsyncStream<ChatEvent> {
        AsyncStream { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { await self?.leave(channelID: channel.id, listener: listener) }
            }
            Task { await self.add(channel, listener: listener, continuation: continuation) }
        }
    }

    func leave(channelID: String, listener: UUID) {
        guard var room = rooms[channelID], let continuation = room.listeners.removeValue(forKey: listener) else { return }
        continuation.finish()
        if room.listeners.isEmpty {
            room.subscribeTask?.cancel()
            rooms[channelID] = nil
            unsubscribe(room.subscriptionIDs + room.moderationIDs, channel: room.channel)
            scheduleIdleClose()
        } else {
            rooms[channelID] = room
        }
    }

    /// Reconnects when the connection is stale or has given up, as on returning to the foreground or getting the
    /// network back.
    func wake() {
        guard !rooms.isEmpty else { return }
        let stale = sockets.isEmpty || gaveUp || Date().timeIntervalSince(lastKeepalive) > Double(keepaliveSeconds)
        guard stale else { return }
        MidgarLog.info("EventSub hub wake → reconnect", category: .eventsub)
        attempt = 0
        connect()
    }

    /// Adds or removes the moderator subscriptions of every open chat after Moderator Tools was turned on or off or
    /// its scopes were granted.
    func refreshModeration() async {
        guard let sessionID else { return }
        guard let token = try? await auth.validAccessToken(), let user = await auth.currentUser() else { return }
        for channelID in rooms.keys {
            guard let room = rooms[channelID], room.subscribed else { continue }
            let applies = await ModerationAccess.shared.toolsApply(to: channelID)
            if applies, room.moderationIDs.isEmpty {
                let ids = await subscriber.createModeratorSubscriptions(broadcasterID: channelID, moderatorID: user.id, sessionID: sessionID, token: token)
                guard self.sessionID == sessionID, rooms[channelID] != nil else {
                    await subscriber.deleteSubscriptions(ids, token: token)
                    continue
                }
                rooms[channelID]?.moderationIDs = ids
            } else if !applies, !room.moderationIDs.isEmpty {
                rooms[channelID]?.moderationIDs = []
                await subscriber.deleteSubscriptions(room.moderationIDs, token: token)
            }
        }
    }

    private func add(_ channel: ChannelInfo, listener: UUID, continuation: AsyncStream<ChatEvent>.Continuation) {
        idleTask?.cancel()
        idleTask = nil
        if var room = rooms[channel.id] {
            room.listeners[listener] = continuation
            rooms[channel.id] = room
            continuation.yield(.connection(room.subscribed ? .connected : .connecting))
            return
        }
        var room = Room(channel: channel)
        room.listeners[listener] = continuation
        rooms[channel.id] = room
        continuation.yield(.connection(.connecting))
        if let sessionID, !gaveUp {
            subscribe(channel.id, sessionID: sessionID)
        } else if sockets.isEmpty || gaveUp {
            attempt = 0
            connect()
        }
    }

    private func connect() {
        teardownSockets()
        gaveUp = false
        sessionID = nil
        for id in rooms.keys {
            rooms[id]?.subscribed = false
            rooms[id]?.subscriptionIDs = []
            rooms[id]?.moderationIDs = []
            rooms[id]?.subscribeTask?.cancel()
        }
        broadcast(.connection(attempt == 0 ? .connecting : .reconnecting(attempt: attempt)))
        liveGeneration = openSocket(at: endpoint)
    }

    @discardableResult
    private func openSocket(at url: URL) -> Int {
        let generation = nextGeneration
        nextGeneration += 1
        let task = socketClient.open(url)
        sockets[generation] = task
        task.resume()
        Task { [weak self] in
            await self?.receiveLoop(generation: generation)
        }
        return generation
    }

    private func receiveLoop(generation: Int) async {
        while true {
            guard let task = sockets[generation] else { return }
            do {
                guard let frame = try await task.receive() else { continue }
                let data: Data
                switch frame {
                case .binary(let value): data = value
                case .text(let value): data = Data(value.utf8)
                }
                await handle(data, generation: generation)
            } catch {
                if Task.isCancelled { return }
                guard sockets[generation] != nil else { return }
                if generation == liveGeneration {
                    MidgarLog.notice("EventSub hub receive failed: \(error)", category: .eventsub)
                    scheduleReconnect()
                } else {
                    sockets[generation] = nil
                }
                return
            }
        }
    }

    private func handle(_ data: Data, generation: Int) async {
        let decoded: EventSubMessage
        do {
            decoded = try EventSubMessage.decode(data)
        } catch {
            MidgarLog.notice("EventSub decode failed: \(error)", category: .eventsub)
            return
        }
        let isReconnect = generation != liveGeneration

        switch decoded {
        case .welcome(let id, let keepalive):
            keepaliveSeconds = keepalive ?? defaultKeepalive
            lastKeepalive = Date()
            startWatchdog()
            if isReconnect {
                promote(generation: generation)
                sessionID = id
                attempt = 0
                MidgarLog.info("EventSub hub moved to a new session, \(rooms.count) chat(s) carried over", category: .eventsub)
            } else {
                sessionID = id
                for channelID in rooms.keys { subscribe(channelID, sessionID: id) }
            }

        case .keepalive:
            lastKeepalive = Date()

        case .notification(let subscriptionType, let broadcasterID, let event):
            lastKeepalive = Date()
            guard let broadcasterID, let room = rooms[broadcasterID] else { return }
            do {
                let chatEvent = try EventSubMapper.chatEvent(subscriptionType: subscriptionType, eventData: event, timestamp: Date())
                room.send(chatEvent)
            } catch {
                MidgarLog.notice("EventSub map \(subscriptionType) failed: \(error)", category: .eventsub)
            }

        case .reconnect(let urlString):
            guard generation == liveGeneration else { return }
            guard let url = URL(string: urlString) else {
                scheduleReconnect()
                return
            }
            MidgarLog.info("EventSub hub session_reconnect", category: .eventsub)
            openSocket(at: url)

        case .revocation(let reason, let subscriptionType, let broadcasterID):
            MidgarLog.notice("EventSub revocation \(subscriptionType ?? "?") for \(broadcasterID ?? "?"): \(reason)", category: .eventsub)
            guard let broadcasterID, let room = rooms[broadcasterID] else { return }
            if Self.isPermanentRevocation(reason) {
                rooms[broadcasterID]?.subscribed = false
                room.send(.connection(.disconnected(reason: String(localized: "Chat unavailable"))))
            } else if subscriptionType == "channel.chat.message", let sessionID {
                room.send(.notice(SystemNotice(text: String(localized: "Chat subscription revoked. Reconnecting."), isError: true)))
                subscribe(broadcasterID, sessionID: sessionID, after: 2)
            }
        }
    }

    private static func isPermanentRevocation(_ reason: String) -> Bool {
        ["authorization_revoked", "user_removed", "version_removed"].contains(reason)
    }

    private func promote(generation: Int) {
        guard sockets[generation] != nil else { return }
        if let old = sockets[liveGeneration], liveGeneration != generation {
            old.close()
            sockets[liveGeneration] = nil
        }
        liveGeneration = generation
    }

    private func subscribe(_ channelID: String, sessionID: String, after delay: Double = 0) {
        guard var room = rooms[channelID] else { return }
        room.subscribeTask?.cancel()
        room.subscribeTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            await self?.createSubscriptions(channelID: channelID, sessionID: sessionID)
        }
        rooms[channelID] = room
    }

    private func createSubscriptions(channelID: String, sessionID: String) async {
        guard let channel = rooms[channelID]?.channel else { return }
        do {
            let token = try await auth.validAccessToken()
            guard let user = await auth.currentUser() else { throw APIError.unauthorized }
            if let sessionUserID, sessionUserID != user.id {
                MidgarLog.info("EventSub hub: the viewer changed, starting a new session", category: .eventsub)
                self.sessionUserID = user.id
                attempt = 0
                connect()
                return
            }
            sessionUserID = user.id
            let ids = try await subscriber.createChatSubscriptions(broadcasterID: channel.id, userID: user.id, sessionID: sessionID, token: token)
            guard self.sessionID == sessionID, rooms[channelID] != nil else {
                await subscriber.deleteSubscriptions(ids, token: token)
                return
            }
            rooms[channelID]?.subscriptionIDs = ids
            rooms[channelID]?.subscribed = true
            rooms[channelID]?.attempt = 0
            rooms[channelID]?.send(.connection(.connected))
            MidgarLog.info("EventSub hub subscribed to \(channel.broadcasterLogin) (\(rooms.count) chat(s) on one connection)", category: .eventsub)
            if await ModerationAccess.shared.toolsApply(to: channelID) {
                let moderation = await subscriber.createModeratorSubscriptions(broadcasterID: channel.id, moderatorID: user.id, sessionID: sessionID, token: token)
                guard self.sessionID == sessionID, rooms[channelID] != nil else {
                    await subscriber.deleteSubscriptions(moderation, token: token)
                    return
                }
                rooms[channelID]?.moderationIDs = moderation
                MidgarLog.info("EventSub hub: moderator tools on in \(channel.broadcasterLogin) (\(moderation.count) subscription(s))", category: .eventsub)
            }
        } catch {
            guard !Task.isCancelled, self.sessionID == sessionID, let room = rooms[channelID] else { return }
            let apiError = error as? APIError
            if apiError == .unauthorized || apiError == .forbidden {
                MidgarLog.notice("EventSub subscribe to \(channel.broadcasterLogin) unauthorized", category: .eventsub)
                room.send(.connection(.disconnected(reason: String(localized: "Sign in to chat"))))
                return
            }
            MidgarLog.error("EventSub subscription to \(channel.broadcasterLogin) failed: \(error)", category: .eventsub)
            let tries = room.attempt + 1
            rooms[channelID]?.attempt = tries
            guard tries <= Self.maxAttempts else {
                room.send(.connection(.disconnected(reason: String(localized: "Tap to reconnect"))))
                return
            }
            room.send(.connection(.reconnecting(attempt: tries)))
            var delay = Self.backoffSeconds(attempt: tries)
            if case .rateLimited(let resetAt)? = apiError {
                delay = max(delay, max(5, resetAt?.timeIntervalSinceNow ?? 15) + Double.random(in: 0...2))
            }
            subscribe(channelID, sessionID: sessionID, after: delay)
        }
    }

    private func unsubscribe(_ ids: [String], channel: ChannelInfo) {
        guard !ids.isEmpty else { return }
        let subscriber = self.subscriber
        let auth = self.auth
        Task {
            guard let token = try? await auth.validAccessToken() else { return }
            await subscriber.deleteSubscriptions(ids, token: token)
            MidgarLog.info("EventSub hub left \(channel.broadcasterLogin)", category: .eventsub)
        }
    }

    private func scheduleIdleClose() {
        guard rooms.isEmpty else { return }
        idleTask?.cancel()
        let wait = idleClose
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.closeIfIdle()
        }
    }

    private func closeIfIdle() {
        guard rooms.isEmpty else { return }
        MidgarLog.info("EventSub hub closing: no chat open", category: .eventsub)
        teardownSockets()
        sessionID = nil
        attempt = 0
    }

    private func broadcast(_ event: ChatEvent) {
        for room in rooms.values { room.send(event) }
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        let timeout = keepaliveSeconds
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                if await self.keepaliveExpired(timeout: timeout) {
                    await self.handleWatchdogTimeout()
                    return
                }
            }
        }
    }

    private func keepaliveExpired(timeout: Int) -> Bool {
        Date().timeIntervalSince(lastKeepalive) > Double(timeout) + 5
    }

    private func handleWatchdogTimeout() {
        guard !rooms.isEmpty else { return }
        MidgarLog.notice("EventSub hub keepalive watchdog fired, reconnecting", category: .eventsub)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        teardownSockets()
        sessionID = nil
        guard !rooms.isEmpty else { return }
        attempt += 1
        guard attempt <= Self.maxAttempts else {
            MidgarLog.notice("EventSub hub gave up after \(attempt - 1) attempts", category: .eventsub)
            gaveUp = true
            broadcast(.connection(.disconnected(reason: String(localized: "Tap to reconnect"))))
            return
        }
        let delay = Self.backoffSeconds(attempt: attempt)
        broadcast(.connection(.reconnecting(attempt: attempt)))
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            await self?.connect()
        }
    }

    private static let maxAttempts = 10

    private func teardownSockets() {
        reconnectTask?.cancel()
        reconnectTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        for task in sockets.values {
            task.close()
        }
        sockets.removeAll()
    }

    private static func backoffSeconds(attempt: Int) -> Double {
        let capped = min(attempt, 4)
        let base = pow(2.0, Double(capped - 1))
        let jitter = Double.random(in: 0...0.5)
        return min(base, 8.0) + jitter
    }
}
