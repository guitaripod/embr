import Foundation
import EmbrCore

/// A channel's chat for a signed-in viewer, carried on the connection every open chat shares (``EventSubChatHub``).
/// Sending goes through the Twitch API, not through this source.
actor EventSubChatSource: ChatSource {
    private let channel: ChannelInfo
    private let hub: EventSubChatHub
    private let listener = UUID()

    init(channel: ChannelInfo, hub: EventSubChatHub = .shared) {
        self.channel = channel
        self.hub = hub
    }

    nonisolated func start() -> AsyncStream<ChatEvent> {
        hub.join(channel, listener: listener)
    }

    func stop() async {
        await hub.leave(channelID: channel.id, listener: listener)
    }

    func send(_ text: String, replyParentID: String?) async throws -> SendResult {
        throw APIError.invalidRequest("EventSub chat source does not send")
    }

    func wake() async {
        await hub.wake()
    }
}
