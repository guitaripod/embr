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
        Task { [weak self] in
            guard let self else { return }
            let ids = Set(await DatabaseManager.shared.blockedUsers().map(\.userID))
            if let snapshot = await self.store.setBlocked(ids) {
                self.snapshotSubject.send(snapshot)
            }
        }
    }

    func block(userID: String, login: String) {
        Task {
            await DatabaseManager.shared.setBlockedUser(userID: userID, login: login)
            if let snapshot = await store.block(userID) {
                snapshotSubject.send(snapshot)
            }
            noticeSubject.send(SystemNotice(text: "Blocked \(login)"))
        }
    }

    func deleteMessage(messageID: String) {
        moderate("delete the message") { try await self.room.deleteMessage(messageID) }
    }

    func banUser(userID: String) {
        moderate("ban") { try await self.room.banUser(userID: userID, duration: nil, reason: nil) }
    }

    func timeoutUser(userID: String, duration: Int) {
        moderate("time out") { try await self.room.banUser(userID: userID, duration: duration, reason: nil) }
    }

    private func moderate(_ label: String, _ op: @escaping () async throws -> Void) {
        Task {
            do { try await op() }
            catch { noticeSubject.send(SystemNotice(text: "Couldn't \(label) — \(Self.describeCommandError(error))", isError: true)) }
        }
    }

    enum CommandResult: Sendable { case notCommand, handled }

    func runCommand(_ text: String) async -> CommandResult {
        guard text.hasPrefix("/") else { return .notCommand }
        let parts = text.dropFirst().split(separator: " ").map(String.init)
        guard let cmd = parts.first?.lowercased() else { return .notCommand }
        let args = Array(parts.dropFirst())
        let targetLogin = args.first.map { $0.hasPrefix("@") ? String($0.dropFirst()) : $0 }

        switch cmd {
        case "help":
            noticeSubject.send(SystemNotice(text: "Commands: /ban /timeout <sec> /unban /block /unblock <user>"))
            return .handled
        case "ban", "timeout", "unban", "block", "unblock":
            guard let login = targetLogin, !login.isEmpty else {
                noticeSubject.send(SystemNotice(text: "Usage: /\(cmd) <user>", isError: true))
                return .handled
            }
            guard let user = await room.lookupUser(login: login) else {
                noticeSubject.send(SystemNotice(text: "User \(login) not found", isError: true))
                return .handled
            }
            await runUserCommand(cmd, user: user, login: login, args: args)
            return .handled
        default:
            return .notCommand
        }
    }

    private func runUserCommand(_ cmd: String, user: TwitchUser, login: String, args: [String]) async {
        do {
            switch cmd {
            case "ban":
                let reason = args.dropFirst().joined(separator: " ")
                try await room.banUser(userID: user.id, duration: nil, reason: reason.isEmpty ? nil : reason)
                noticeSubject.send(SystemNotice(text: "Banned \(login)"))
            case "timeout":
                let seconds = args.count > 1 ? (Int(args[1]) ?? 600) : 600
                try await room.banUser(userID: user.id, duration: seconds, reason: nil)
                noticeSubject.send(SystemNotice(text: "Timed out \(login) for \(seconds)s"))
            case "unban":
                try await room.unbanUser(userID: user.id)
                noticeSubject.send(SystemNotice(text: "Unbanned \(login)"))
            case "block":
                await DatabaseManager.shared.setBlockedUser(userID: user.id, login: user.login)
                if let snapshot = await store.block(user.id) { snapshotSubject.send(snapshot) }
                noticeSubject.send(SystemNotice(text: "Blocked \(login)"))
            case "unblock":
                await DatabaseManager.shared.removeBlockedUser(userID: user.id)
                noticeSubject.send(SystemNotice(text: "Unblocked \(login) · reopen chat to show"))
            default:
                break
            }
        } catch {
            noticeSubject.send(SystemNotice(text: "Failed: /\(cmd) \(login) — \(Self.describeCommandError(error))", isError: true))
        }
    }

    private static func describeCommandError(_ error: Error) -> String {
        guard let api = error as? APIError else { return "error" }
        switch api {
        case .unauthorized: return "sign in required"
        case .forbidden: return "not a moderator here"
        case .rateLimited: return "rate limited"
        default: return "error"
        }
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

    func wake() {
        Task { await room.wake() }
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
    private var blockedUserIDs: Set<String> = []

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

    func setBlocked(_ ids: Set<String>) -> ChatSnapshot? {
        blockedUserIDs = ids
        guard !ids.isEmpty else { return nil }
        let before = rows.count
        rows.removeAll { ids.contains($0.message.author.id) }
        frozenRows.removeAll { ids.contains($0.message.author.id) }
        guard rows.count != before else { return nil }
        rebuildIndex()
        return currentSnapshot()
    }

    func block(_ userID: String) -> ChatSnapshot? {
        blockedUserIDs.insert(userID)
        let before = rows.count
        rows.removeAll { $0.message.author.id == userID }
        frozenRows.removeAll { $0.message.author.id == userID }
        if rows.count != before { rebuildIndex() }
        return currentSnapshot()
    }

    func append(_ messages: [ChatMessage]) -> ChatSnapshot? {
        guard !messages.isEmpty else { return nil }
        var added = 0
        for message in messages {
            if blockedUserIDs.contains(message.author.id) { continue }
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
