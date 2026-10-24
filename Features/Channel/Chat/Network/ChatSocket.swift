import Foundation

/// One open WebSocket to a chat service. A thin handle over `URLSessionWebSocketTask`; the chat sources decide when to read, write and close it.
nonisolated struct ChatSocket: Sendable {
    enum Frame: Sendable {
        case text(String)
        case binary(Data)
    }

    fileprivate let task: URLSessionWebSocketTask

    func resume() {
        task.resume()
    }

    /// The next frame, or nil for a frame kind this client does not know.
    func receive() async throws -> Frame? {
        switch try await task.receive() {
        case .string(let value): return .text(value)
        case .data(let value): return .binary(value)
        @unknown default: return nil
        }
    }

    func send(text: String, completion: @escaping @Sendable (Error?) -> Void) {
        task.send(.string(text), completionHandler: completion)
    }

    func close() {
        task.cancel(with: .goingAway, reason: nil)
    }
}

/// Owns the `URLSession` the chat sockets of one source share, creating it on first use and dropping it on `invalidate()`.
final class ChatSocketClient {
    private var session: URLSession?

    func open(_ url: URL) -> ChatSocket {
        let session = self.session ?? URLSession(configuration: .default)
        self.session = session
        return ChatSocket(task: session.webSocketTask(with: url))
    }

    func invalidate() {
        session?.invalidateAndCancel()
        session = nil
    }
}
