import Foundation
import EmbrCore

struct ChatRow: Sendable, Hashable, Identifiable {
    var id: String { message.id }
    let message: ChatMessage
    var laidOut: LaidOutMessage?

    init(message: ChatMessage, laidOut: LaidOutMessage? = nil) {
        self.message = message
        self.laidOut = laidOut
    }

    func withModeration(_ state: ModerationState) -> ChatRow {
        guard message.moderation != state else { return self }
        var updated = message
        updated.moderation = state
        return ChatRow(message: updated, laidOut: laidOut)
    }

    static func == (lhs: ChatRow, rhs: ChatRow) -> Bool {
        lhs.message.id == rhs.message.id && lhs.message.moderation == rhs.message.moderation
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(message.id)
        hasher.combine(message.moderation)
    }
}

struct ChatSnapshot: Sendable {
    let rows: [ChatRow]
    let isPaused: Bool
    let newCount: Int

    init(rows: [ChatRow], isPaused: Bool, newCount: Int) {
        self.rows = rows
        self.isPaused = isPaused
        self.newCount = newCount
    }
}
