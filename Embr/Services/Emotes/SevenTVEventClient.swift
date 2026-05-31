import Foundation
import EmbrCore

actor SevenTVEventClient: EmoteEventStreaming {
    private static let endpoint = URL(string: "wss://events.7tv.io/v3")!
    private static let reconnectDelay: UInt64 = 5_000_000_000

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated func updates(emoteSetID: String) -> AsyncStream<EmoteSetUpdate> {
        AsyncStream { continuation in
            let task = Task {
                await self.run(emoteSetID: emoteSetID, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(emoteSetID: String, continuation: AsyncStream<EmoteSetUpdate>.Continuation) async {
        while !Task.isCancelled {
            let socket = session.webSocketTask(with: Self.endpoint)
            socket.resume()
            await consume(socket: socket, emoteSetID: emoteSetID, continuation: continuation)
            socket.cancel(with: .goingAway, reason: nil)
            if Task.isCancelled { break }
            AppLogger.shared.warn("7TV events disconnected, reconnecting", category: .emote)
            try? await Task.sleep(nanoseconds: Self.reconnectDelay)
        }
        continuation.finish()
    }

    private func consume(
        socket: URLSessionWebSocketTask,
        emoteSetID: String,
        continuation: AsyncStream<EmoteSetUpdate>.Continuation
    ) async {
        while !Task.isCancelled {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await socket.receive()
            } catch {
                AppLogger.shared.warn("7TV events receive failed: \(error)", category: .emote)
                return
            }
            guard let data = data(from: message) else { continue }
            let event: SevenTVEvent
            do {
                event = try SevenTVEventFrame.decode(data)
            } catch {
                continue
            }
            switch event {
            case .hello:
                await subscribe(socket: socket, emoteSetID: emoteSetID)
            case .dispatch(let update):
                continuation.yield(update)
            case .heartbeat, .other:
                continue
            }
        }
    }

    private func subscribe(socket: URLSessionWebSocketTask, emoteSetID: String) async {
        guard let frame = try? SevenTVEventFrame.subscribeFrame(emoteSetID: emoteSetID) else { return }
        do {
            try await socket.send(.data(frame))
            AppLogger.shared.info("7TV subscribed to emote set \(emoteSetID)", category: .emote)
        } catch {
            AppLogger.shared.warn("7TV subscribe failed: \(error)", category: .emote)
        }
    }

    private func data(from message: URLSessionWebSocketTask.Message) -> Data? {
        switch message {
        case .data(let data): return data
        case .string(let string): return string.data(using: .utf8)
        @unknown default: return nil
        }
    }
}
