import Foundation
import EmbrCore

actor EventSubChatSource: ChatSource {
    private let channel: ChannelInfo
    private let api: TwitchAPIProviding
    private let auth: AuthControlling
    private let subscriber: EventSubSubscriber
    private let logger = AppLogger.shared

    private let endpoint = URL(string: "wss://eventsub.wss.twitch.tv/ws?keepalive_timeout_seconds=30")!
    private let defaultKeepalive = 30

    private var session: URLSession?
    private var sockets: [Int: URLSessionWebSocketTask] = [:]
    private var liveGeneration = 0
    private var nextGeneration = 0
    private var watchdogTask: Task<Void, Never>?
    private var subscribeTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var continuation: AsyncStream<ChatEvent>.Continuation?
    private var keepaliveSeconds: Int
    private var lastKeepalive = Date()
    private var attempt = 0
    private var stopped = false

    init(
        channel: ChannelInfo,
        api: TwitchAPIProviding,
        auth: AuthControlling,
        subscriber: EventSubSubscriber = EventSubSubscriber()
    ) {
        self.channel = channel
        self.api = api
        self.auth = auth
        self.subscriber = subscriber
        self.keepaliveSeconds = defaultKeepalive
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
        throw APIError.invalidRequest("EventSub chat source does not send")
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
        teardownSockets()
        continuation?.yield(.connection(attempt == 0 ? .connecting : .reconnecting(attempt: attempt)))
        let generation = openSocket(at: endpoint)
        liveGeneration = generation
    }

    @discardableResult
    private func openSocket(at url: URL) -> Int {
        let session = self.session ?? URLSession(configuration: .default)
        self.session = session
        let generation = nextGeneration
        nextGeneration += 1
        let task = session.webSocketTask(with: url)
        sockets[generation] = task
        task.resume()
        Task { [weak self] in
            await self?.receiveLoop(generation: generation)
        }
        return generation
    }

    private func receiveLoop(generation: Int) async {
        while !stopped {
            guard let task = sockets[generation] else { return }
            do {
                let message = try await task.receive()
                let data: Data
                switch message {
                case .data(let value): data = value
                case .string(let value): data = Data(value.utf8)
                @unknown default: continue
                }
                await handle(data, generation: generation)
            } catch {
                if stopped || Task.isCancelled { return }
                guard sockets[generation] != nil else { return }
                if generation == liveGeneration {
                    logger.warn("EventSub receive failed: \(error)", category: .eventsub)
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
            logger.warn("EventSub decode failed: \(error)", category: .eventsub)
            return
        }

        let isReconnect = generation != liveGeneration

        switch decoded {
        case .welcome(let sessionID, let keepalive):
            if isReconnect {
                promote(generation: generation)
            }
            keepaliveSeconds = keepalive ?? defaultKeepalive
            lastKeepalive = Date()
            startWatchdog()
            if isReconnect {
                attempt = 0
            } else {
                scheduleSubscription(sessionID: sessionID)
            }

        case .keepalive:
            lastKeepalive = Date()

        case .notification(let subscriptionType, let event):
            lastKeepalive = Date()
            do {
                let chatEvent = try EventSubMapper.chatEvent(
                    subscriptionType: subscriptionType,
                    eventData: event,
                    timestamp: Date()
                )
                continuation?.yield(chatEvent)
            } catch {
                logger.warn("EventSub map \(subscriptionType) failed: \(error)", category: .eventsub)
            }

        case .reconnect(let urlString):
            guard generation == liveGeneration else { return }
            guard let url = URL(string: urlString) else {
                scheduleReconnect()
                return
            }
            logger.info("EventSub session_reconnect", category: .eventsub)
            openSocket(at: url)

        case .revocation(let reason):
            logger.warn("EventSub revocation: \(reason)", category: .eventsub)
            if Self.isPermanentRevocation(reason) {
                teardownSockets()
                continuation?.yield(.connection(.disconnected(reason: "Chat unavailable")))
            } else {
                continuation?.yield(.notice(SystemNotice(text: "Chat subscription revoked. Reconnecting.", isError: true)))
                scheduleReconnect()
            }
        }
    }

    private static func isPermanentRevocation(_ reason: String) -> Bool {
        ["authorization_revoked", "user_removed", "version_removed"].contains(reason)
    }

    func wake() async {
        guard !stopped else { return }
        let stale = sockets.isEmpty || Date().timeIntervalSince(lastKeepalive) > Double(keepaliveSeconds)
        guard stale else { return }
        logger.info("EventSub wake → reconnect", category: .eventsub)
        attempt = 0
        connect()
    }

    private func promote(generation: Int) {
        guard sockets[generation] != nil else { return }
        if let old = sockets[liveGeneration], liveGeneration != generation {
            old.cancel(with: .goingAway, reason: nil)
            sockets[liveGeneration] = nil
        }
        liveGeneration = generation
    }

    private func scheduleSubscription(sessionID: String) {
        subscribeTask?.cancel()
        subscribeTask = Task { [weak self] in
            await self?.createSubscription(sessionID: sessionID)
        }
    }

    private func createSubscription(sessionID: String) async {
        do {
            let token = try await auth.validAccessToken()
            guard let user = await auth.currentUser() else {
                throw APIError.unauthorized
            }
            try await subscriber.createChatSubscription(
                broadcasterID: channel.id,
                userID: user.id,
                sessionID: sessionID,
                token: token
            )
            guard !stopped else { return }
            attempt = 0
            continuation?.yield(.connection(.connected))
            logger.info("EventSub subscribed to chat for \(channel.broadcasterLogin)", category: .eventsub)
        } catch {
            if stopped { return }
            let apiError = error as? APIError
            if apiError == .unauthorized || apiError == .forbidden {
                logger.warn("EventSub subscribe unauthorized; chat disabled until re-auth", category: .eventsub)
                teardownSockets()
                continuation?.yield(.connection(.disconnected(reason: "Sign in to chat")))
                return
            }
            logger.error("EventSub subscription failed: \(error)", category: .eventsub)
            scheduleReconnect()
        }
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
        guard !stopped else { return }
        logger.warn("EventSub keepalive watchdog fired, reconnecting", category: .eventsub)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        teardownSockets()
        attempt += 1
        guard attempt <= Self.maxAttempts else {
            logger.warn("EventSub gave up after \(attempt - 1) attempts", category: .eventsub)
            continuation?.yield(.connection(.disconnected(reason: "Tap to reconnect")))
            return
        }
        let delay = Self.backoffSeconds(attempt: attempt)
        continuation?.yield(.connection(.reconnecting(attempt: attempt)))
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
        subscribeTask?.cancel()
        subscribeTask = nil
        for task in sockets.values {
            task.cancel(with: .goingAway, reason: nil)
        }
        sockets.removeAll()
    }

    private func teardown() {
        teardownSockets()
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
