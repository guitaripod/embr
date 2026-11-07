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
        var staleIDs: [String] = []
        var subscribed = false
        var stopped = false
        var subscribeTask: Task<Void, Never>?
        var moderationTask: Task<Void, Never>?
        var generation = 0
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
    private var nextRoomGeneration = 0
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
            unsubscribe(room.subscriptionIDs + room.moderationIDs + room.staleIDs, channel: room.channel)
            scheduleIdleClose()
        } else {
            rooms[channelID] = room
        }
    }

    /// Reconnects when the connection is stale or has given up, as on returning to the foreground, getting the network
    /// back or tapping to reconnect, and on a live connection subscribes again every chat that stopped trying.
    func wake() {
        guard !rooms.isEmpty else { return }
        let stale = sockets.isEmpty || gaveUp || Date().timeIntervalSince(lastKeepalive) > Double(keepaliveSeconds)
        if stale {
            MidgarLog.info("EventSub hub wake → reconnect", category: .eventsub)
            attempt = 0
            connect()
            return
        }
        guard sessionID != nil else { return }
        for (channelID, room) in rooms where room.stopped {
            MidgarLog.info("EventSub hub wake → subscribe to \(room.channel.broadcasterLogin) again", category: .eventsub)
            rooms[channelID]?.attempt = 0
            subscribe(channelID)
        }
    }

    /// Adds or removes the moderator subscriptions of every open chat after Moderator Tools was turned on or off or
    /// its scopes were granted.
    func refreshModeration() {
        for channelID in rooms.keys { syncModeration(channelID) }
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
        if sessionID != nil, !gaveUp {
            subscribe(channel.id)
        } else if sockets.isEmpty || gaveUp {
            attempt = 0
            connect()
        }
    }

    private func connect() {
        teardownSockets()
        gaveUp = false
        sessionID = nil
        resetRooms()
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
                for (channelID, room) in rooms where !room.subscribed { subscribe(channelID) }
            } else {
                sessionID = id
                for channelID in rooms.keys { subscribe(channelID) }
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
            if let subscriptionType, EventSubSubscriptionRequest.isModeratorType(subscriptionType) {
                dropModeration(broadcasterID)
            } else if Self.isPermanentRevocation(reason) {
                rooms[broadcasterID]?.subscribed = false
                rooms[broadcasterID]?.stopped = true
                room.send(.connection(.disconnected(reason: String(localized: "Chat unavailable"))))
            } else if subscriptionType == "channel.chat.message", sessionID != nil {
                room.send(.notice(SystemNotice(text: String(localized: "Chat subscription revoked. Reconnecting."), isError: true)))
                subscribe(broadcasterID, after: 2)
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

    /// Starts a fresh subscription of the channel's chat, after a delay when retrying. The subscriptions it still holds
    /// are deleted first, and work still running for an earlier one is dropped. It subscribes on whichever session is
    /// open when it runs, and waits for the next welcome when none is.
    private func subscribe(_ channelID: String, after delay: Double = 0) {
        guard var room = rooms[channelID] else { return }
        room.subscribeTask?.cancel()
        nextRoomGeneration += 1
        let generation = nextRoomGeneration
        room.generation = generation
        room.staleIDs += room.subscriptionIDs + room.moderationIDs
        room.subscriptionIDs = []
        room.moderationIDs = []
        room.subscribed = false
        room.stopped = false
        room.subscribeTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            await self?.createSubscriptions(channelID: channelID, generation: generation)
        }
        rooms[channelID] = room
    }

    /// Whether work started for a chat's subscription still belongs to it: the session is the same and the chat has
    /// not been subscribed again or closed since.
    private func isCurrent(_ channelID: String, sessionID: String, generation: Int) -> Bool {
        self.sessionID == sessionID && rooms[channelID]?.generation == generation
    }

    private func createSubscriptions(channelID: String, generation: Int) async {
        guard let sessionID, let channel = rooms[channelID]?.channel, rooms[channelID]?.generation == generation else { return }
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
            guard isCurrent(channelID, sessionID: sessionID, generation: generation) else { return }
            if let stale = rooms[channelID]?.staleIDs, !stale.isEmpty {
                rooms[channelID]?.staleIDs = []
                await subscriber.deleteSubscriptions(stale, token: token)
            }
            let ids = try await subscriber.createChatSubscriptions(broadcasterID: channel.id, userID: user.id, sessionID: sessionID, token: token)
            guard isCurrent(channelID, sessionID: sessionID, generation: generation) else {
                await subscriber.deleteSubscriptions(ids, token: token)
                return
            }
            rooms[channelID]?.subscriptionIDs = ids
            rooms[channelID]?.subscribed = true
            rooms[channelID]?.attempt = 0
            rooms[channelID]?.send(.connection(.connected))
            MidgarLog.info("EventSub hub subscribed to \(channel.broadcasterLogin) (\(rooms.count) chat(s) on one connection)", category: .eventsub)
            syncModeration(channelID)
        } catch {
            guard !Task.isCancelled, isCurrent(channelID, sessionID: sessionID, generation: generation), let room = rooms[channelID] else { return }
            let apiError = error as? APIError
            if apiError == .unauthorized || apiError == .forbidden {
                MidgarLog.notice("EventSub subscribe to \(channel.broadcasterLogin) unauthorized", category: .eventsub)
                rooms[channelID]?.stopped = true
                room.send(.connection(.disconnected(reason: String(localized: "Sign in to chat"))))
                return
            }
            MidgarLog.error("EventSub subscription to \(channel.broadcasterLogin) failed: \(error)", category: .eventsub)
            let tries = room.attempt + 1
            rooms[channelID]?.attempt = tries
            guard tries <= Self.maxAttempts else {
                rooms[channelID]?.stopped = true
                room.send(.connection(.disconnected(reason: String(localized: "Tap to reconnect"))))
                return
            }
            room.send(.connection(.reconnecting(attempt: tries)))
            var delay = Self.backoffSeconds(attempt: tries)
            if case .rateLimited(let resetAt)? = apiError {
                delay = max(delay, max(5, resetAt?.timeIntervalSinceNow ?? 15) + Double.random(in: 0...2))
            }
            subscribe(channelID, after: delay)
        }
    }

    /// Queues a check of the chat's moderator subscriptions behind any check still running for it, so two never
    /// create the same subscriptions at once.
    private func syncModeration(_ channelID: String) {
        guard var room = rooms[channelID] else { return }
        let previous = room.moderationTask
        let generation = room.generation
        room.moderationTask = Task { [weak self] in
            await previous?.value
            await self?.reconcileModeration(channelID, generation: generation)
        }
        rooms[channelID] = room
    }

    /// Makes the chat's moderator subscriptions match whether Moderator Tools applies there: creates them when it
    /// does and they are missing, deletes them when it no longer does.
    private func reconcileModeration(_ channelID: String, generation: Int) async {
        guard let sessionID, let room = rooms[channelID], room.subscribed, room.generation == generation else { return }
        let applies = await ModerationAccess.shared.toolsApply(to: channelID)
        guard isCurrent(channelID, sessionID: sessionID, generation: generation), let room = rooms[channelID] else { return }
        if applies, room.moderationIDs.isEmpty {
            guard let token = try? await auth.validAccessToken(), let user = await auth.currentUser() else { return }
            let ids = await subscriber.createModeratorSubscriptions(broadcasterID: channelID, moderatorID: user.id, sessionID: sessionID, token: token)
            guard isCurrent(channelID, sessionID: sessionID, generation: generation) else {
                await subscriber.deleteSubscriptions(ids, token: token)
                return
            }
            rooms[channelID]?.moderationIDs = ids
            MidgarLog.info("EventSub hub: moderator tools on in \(room.channel.broadcasterLogin) (\(ids.count) subscription(s))", category: .eventsub)
        } else if !applies, !room.moderationIDs.isEmpty {
            rooms[channelID]?.moderationIDs = []
            unsubscribe(room.moderationIDs, channel: room.channel)
            MidgarLog.info("EventSub hub: moderator tools off in \(room.channel.broadcasterLogin)", category: .eventsub)
        }
    }

    /// Lets go of a chat's moderator subscriptions after Twitch revoked one, as it does when the viewer stops
    /// moderating there, and forgets which channels they moderate so the next check asks again.
    private func dropModeration(_ channelID: String) {
        guard let room = rooms[channelID], !room.moderationIDs.isEmpty else { return }
        rooms[channelID]?.moderationIDs = []
        unsubscribe(room.moderationIDs, channel: room.channel)
        Task { await ModerationAccess.shared.forget() }
    }

    /// Forgets every chat's subscriptions once their session is gone; Twitch drops them with it.
    private func resetRooms() {
        for id in rooms.keys {
            rooms[id]?.subscribeTask?.cancel()
            rooms[id]?.subscribed = false
            rooms[id]?.subscriptionIDs = []
            rooms[id]?.moderationIDs = []
            rooms[id]?.staleIDs = []
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
        resetRooms()
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
