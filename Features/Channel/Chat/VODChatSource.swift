import Foundation
import EmbrCore
import MidgarCore

/// Replays a VOD's chat at the video's playback position. Twitch serves the comments in
/// offset windows; the source keeps a small queue and asks for the next window as playback
/// nears the end of the one it has loaded.
actor VODChatSource: ChatSource {
    private let channel: ChannelInfo
    private let videoID: String
    private let client: VodCommentsProviding

    private var continuation: AsyncStream<ChatEvent>.Continuation?
    private var queue: [VodComment] = []
    private var seen: Set<String> = []
    private var nextOffset = 0
    private var hasMore = true
    private var loading = false
    private var stopped = false
    private var connected = false
    private var position: TimeInterval = 0
    private var lastPosition: TimeInterval = 0
    private var lastFailure: Date?
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    private let prefetchWindow: TimeInterval = 30
    private let seekThreshold: TimeInterval = 4

    init(channel: ChannelInfo, videoID: String, client: VodCommentsProviding = VodChatClient.shared) {
        self.channel = channel
        self.videoID = videoID
        self.client = client
    }

    nonisolated func start() -> AsyncStream<ChatEvent> {
        AsyncStream { continuation in
            Task { await self.begin(continuation) }
        }
    }

    func stop() async {
        stopped = true
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        queue.removeAll()
        continuation?.yield(.connection(.disconnected(reason: nil)))
        continuation?.finish()
        continuation = nil
    }

    func send(_ text: String, replyParentID: String?) async throws -> SendResult {
        throw APIError.forbidden
    }

    func wake() async {
        guard !stopped else { return }
        await loadNextIfNeeded()
    }

    func setPlayback(seconds: TimeInterval) async {
        guard !stopped else { return }
        let next = max(0, seconds)
        let delta = next - lastPosition
        lastPosition = next
        position = next
        if delta < -seekThreshold || delta > seekThreshold {
            await reload(at: next)
            return
        }
        drain()
        await loadNextIfNeeded()
    }

    private func begin(_ continuation: AsyncStream<ChatEvent>.Continuation) {
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stop() }
        }
        continuation.yield(.connection(.connecting))
        loadTask = Task { [weak self] in
            await self?.loadNext()
        }
    }

    private func reload(at seconds: TimeInterval) async {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        queue.removeAll()
        seen.removeAll()
        nextOffset = max(0, Int(seconds.rounded(.down)))
        hasMore = true
        connected = false
        position = seconds
        lastPosition = seconds
        continuation?.yield(.clearChat)
        await loadNext()
    }

    private func loadNextIfNeeded() async {
        guard !loading, hasMore, !stopped else { return }
        guard let lastOffset = queue.last?.offsetSeconds else {
            await loadNext()
            return
        }
        if position >= TimeInterval(lastOffset) - prefetchWindow {
            await loadNext()
        }
    }

    private func loadNext() async {
        guard !stopped, !loading, hasMore else { return }
        if let lastFailure, Date().timeIntervalSince(lastFailure) < 5 { return }
        loading = true
        let requested = nextOffset
        let current = generation
        do {
            let page = try await client.page(videoID: videoID, offset: requested)
            guard !stopped, current == generation else {
                loading = false
                return
            }
            for comment in page.comments where !seen.contains(comment.id) {
                seen.insert(comment.id)
                queue.append(comment)
            }
            queue.sort { $0.offsetSeconds < $1.offsetSeconds || ($0.offsetSeconds == $1.offsetSeconds && $0.id < $1.id) }
            nextOffset = max(page.nextOffset, requested + 1)
            hasMore = page.hasMore
            lastFailure = nil
            if !connected {
                connected = true
                continuation?.yield(.connection(.connected))
            }
            drain()
            loading = false
        } catch {
            loading = false
            lastFailure = Date()
            MidgarLog.notice("VOD chat fetch failed for \(videoID) at \(requested): \(error)", category: .chat)
            if !connected {
                connected = true
                continuation?.yield(.connection(.connected))
            }
        }
    }

    private func drain() {
        guard !queue.isEmpty else { return }
        let limit = position + 0.75
        var emitted: [VodComment] = []
        while let first = queue.first, TimeInterval(first.offsetSeconds) <= limit {
            emitted.append(queue.removeFirst())
        }
        for comment in emitted {
            continuation?.yield(.message(comment.chatMessage(channelID: channel.id)))
        }
    }
}
