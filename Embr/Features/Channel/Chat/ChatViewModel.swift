import Foundation
import Combine
import EmbrCore

@MainActor
final class ChatViewModel {
    let snapshotSubject = PassthroughSubject<ChatSnapshot, Never>()
    let connectionSubject = PassthroughSubject<ConnectionStatus, Never>()
    let roomStateSubject = PassthroughSubject<RoomState, Never>()
    let catalogSubject = PassthroughSubject<EmoteCatalog, Never>()
    let noticeSubject = PassthroughSubject<SystemNotice, Never>()

    private let room: ChatRoom

    private let store: MessageStore
    private var consumeTask: Task<Void, Never>?
    private var replyParentID: String?

    init(
        room: ChatRoom,
        settings: SettingsStore = SettingsStore.shared,
        currentUserLogin: String? = nil
    ) {
        self.room = room
        self.store = MessageStore(settings: settings.current, currentUserLogin: currentUserLogin)
    }

    var currentReplyParentID: String? { replyParentID }

    func start() {
        guard consumeTask == nil else { return }
        let stream = room.start()
        consumeTask = Task { [weak self] in
            for await event in stream {
                await self?.handle(event)
            }
        }
    }

    func stop() {
        consumeTask?.cancel()
        consumeTask = nil
        Task { await room.stop() }
    }

    func setPaused(_ paused: Bool) {
        Task {
            if let snapshot = await store.setPaused(paused) {
                snapshotSubject.send(snapshot)
            }
        }
    }

    func updateWidth(_ width: CGFloat) {
        Task { await store.updateWidth(width) }
    }

    func setReply(parentID: String?) {
        replyParentID = parentID
    }

    func send(_ text: String) async throws -> SendResult {
        let result = try await room.send(text, replyParentID: replyParentID)
        if result.isSent {
            replyParentID = nil
        }
        return result
    }

    func search(_ query: String) {
        Task {
            let snapshot = await store.search(query)
            snapshotSubject.send(snapshot)
        }
    }

    private func handle(_ event: ChatRoomEvent) async {
        switch event {
        case .catalog(let catalog, let badges):
            await store.setCatalogs(catalog: catalog, badges: badges)
            catalogSubject.send(catalog)
        case .messages(let messages):
            if let snapshot = await store.append(messages) {
                snapshotSubject.send(snapshot)
            }
        case .delete(let messageID):
            if let snapshot = await store.applyModeration(.deleted, messageID: messageID) {
                snapshotSubject.send(snapshot)
            }
        case .clearUser(let userID):
            if let snapshot = await store.clearUser(userID) {
                snapshotSubject.send(snapshot)
            }
        case .clearChat:
            if let snapshot = await store.clearChat() {
                snapshotSubject.send(snapshot)
            }
        case .roomState(let state):
            roomStateSubject.send(state)
        case .connection(let status):
            connectionSubject.send(status)
        case .notice(let notice):
            noticeSubject.send(notice)
        }
    }
}

private actor MessageStore {
    private var rows: [ChatRow] = []
    private var index: [String: Int] = [:]
    private var paused = false
    private var pausedNewCount = 0
    private var frozenRows: [ChatRow] = []

    private var catalog = EmoteCatalog()
    private var badges = BadgeCatalog()
    private var settings: Settings
    private var width: CGFloat = 0
    private var layout: MessageLayout?
    private let currentUserLogin: String?

    private let capacity = 5000
    private let trimFraction = 0.2
    private let liveWindow = 500

    init(settings: Settings, currentUserLogin: String?) {
        self.settings = settings
        self.currentUserLogin = currentUserLogin
    }

    func updateWidth(_ width: CGFloat) {
        guard width > 0, width != self.width else { return }
        self.width = width
        rebuildLayout()
    }

    func setCatalogs(catalog: EmoteCatalog, badges: BadgeCatalog) {
        self.catalog = catalog
        self.badges = badges
        rebuildLayout()
    }

    func setPaused(_ paused: Bool) -> ChatSnapshot? {
        guard paused != self.paused else { return nil }
        self.paused = paused
        if !paused {
            pausedNewCount = 0
            frozenRows = []
            return liveSnapshot()
        }
        frozenRows = Array(rows.suffix(liveWindow))
        return frozenSnapshot()
    }

    func append(_ messages: [ChatMessage]) -> ChatSnapshot? {
        guard !messages.isEmpty else { return nil }
        var added = 0
        for message in messages {
            if let existing = index[message.id] {
                rows[existing] = makeRow(message)
            } else {
                index[message.id] = rows.count
                rows.append(makeRow(message))
                added += 1
            }
        }
        trimIfNeeded()
        if paused {
            pausedNewCount += added
            return frozenSnapshot()
        }
        return liveSnapshot()
    }

    func applyModeration(_ state: ModerationState, messageID: String) -> ChatSnapshot? {
        guard let position = index[messageID] else { return nil }
        rows[position] = rows[position].withModeration(state)
        if paused, let i = frozenRows.firstIndex(where: { $0.message.id == messageID }) {
            frozenRows[i] = frozenRows[i].withModeration(state)
        }
        return currentSnapshot()
    }

    func clearUser(_ userID: String) -> ChatSnapshot? {
        var changed = false
        for position in rows.indices where rows[position].message.author.id == userID {
            rows[position] = rows[position].withModeration(.timedOut)
            changed = true
        }
        if paused {
            for i in frozenRows.indices where frozenRows[i].message.author.id == userID {
                frozenRows[i] = frozenRows[i].withModeration(.timedOut)
            }
        }
        return changed ? currentSnapshot() : nil
    }

    func clearChat() -> ChatSnapshot? {
        for position in rows.indices {
            rows[position] = rows[position].withModeration(.deleted)
        }
        if paused {
            for i in frozenRows.indices {
                frozenRows[i] = frozenRows[i].withModeration(.deleted)
            }
        }
        return currentSnapshot()
    }

    func search(_ query: String) -> ChatSnapshot {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return ChatSnapshot(rows: Array(rows.suffix(liveWindow)), isPaused: paused, newCount: pausedNewCount)
        }
        let matches = rows.filter { row in
            row.message.author.displayName.lowercased().contains(trimmed)
                || row.message.author.login.lowercased().contains(trimmed)
                || row.message.plainText.lowercased().contains(trimmed)
        }
        return ChatSnapshot(rows: matches, isPaused: true, newCount: pausedNewCount)
    }

    private func makeRow(_ message: ChatMessage) -> ChatRow {
        guard let layout else { return ChatRow(message: message) }
        return ChatRow(message: message, laidOut: layout.layout(message))
    }

    private func rebuildLayout() {
        guard width > 0 else { return }
        layout = MessageLayout(width: width, settings: settings, catalog: catalog, badges: badges, currentUserLogin: currentUserLogin)
        for position in rows.indices {
            rows[position] = ChatRow(message: rows[position].message, laidOut: layout?.layout(rows[position].message))
        }
    }

    private func trimIfNeeded() {
        guard rows.count > capacity else { return }
        let drop = Int(Double(capacity) * trimFraction)
        rows.removeFirst(drop)
        rebuildIndex()
    }

    private func rebuildIndex() {
        index.removeAll(keepingCapacity: true)
        for (position, row) in rows.enumerated() {
            index[row.message.id] = position
        }
    }

    private func currentSnapshot() -> ChatSnapshot {
        paused ? frozenSnapshot() : liveSnapshot()
    }

    private func liveSnapshot() -> ChatSnapshot {
        let window = rows.suffix(liveWindow)
        return ChatSnapshot(rows: Array(window), isPaused: false, newCount: 0)
    }

    private func frozenSnapshot() -> ChatSnapshot {
        ChatSnapshot(rows: frozenRows, isPaused: true, newCount: pausedNewCount)
    }
}
