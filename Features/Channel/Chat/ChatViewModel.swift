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
    let activitySubject = PassthroughSubject<ChatActivity, Never>()
    let moderationSubject = PassthroughSubject<ModerationQueue, Never>()
    private(set) var moderation = ModerationQueue()

    private let room: ChatRoom
    private let reporter: ReportClient
    private let settings: SettingsStore

    private let store: MessageStore
    private var consumeTask: Task<Void, Never>?
    private var replyParentID: String?
    private var cancellables = Set<AnyCancellable>()
    private var pendingWidth: CGFloat?
    private var widthTask: Task<Void, Never>?
    private var moderationSnapshotTask: Task<Void, Never>?
    private var lastCatalog: EmoteCatalog?
    private var lastRoomState: RoomState?
    private var lastConnection: ConnectionStatus?

    init(
        room: ChatRoom,
        settings: SettingsStore = SettingsStore.shared,
        currentUserLogin: String? = nil,
        reporter: ReportClient = .shared
    ) {
        self.room = room
        self.reporter = reporter
        self.settings = settings
        self.store = MessageStore(
            settings: settings.current,
            currentUserLogin: currentUserLogin,
            filter: settings.current.makeContentFilter()
        )
        Task { [weak self] in
            guard let self else { return }
            let ids = Set(await DatabaseManager.shared.blockedUsers().map(\.userID))
            if let snapshot = await self.store.setBlocked(ids) {
                self.snapshotSubject.send(snapshot)
            }
        }
        settings.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                self?.applyContentFilter(settings.makeContentFilter())
            }
            .store(in: &cancellables)
        settings.changes
            .map(\.moderatorToolsEnabled)
            .removeDuplicates()
            .filter { !$0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.clearModeration() }
            .store(in: &cancellables)
        settings.changes
            .map { _ in () }
            .merge(with: SupporterStore.shared.changes)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.applyLayoutSettings() }
            .store(in: &cancellables)
    }

    /// Empties the moderation queue once Moderator Tools is turned off, which hides its bar and closes the queue.
    private func clearModeration() {
        guard !moderation.isEmpty else { return }
        moderation = ModerationQueue()
        moderationSubject.send(moderation)
    }

    /// Draws the open chat again when its text size, font or a supporter's look changed.
    private func applyLayoutSettings() {
        let current = settings.current
        Task { [weak self] in
            guard let self else { return }
            if let snapshot = await self.store.updateSettings(current) {
                self.snapshotSubject.send(snapshot)
            }
        }
    }

    private func applyContentFilter(_ filter: ContentFilter) {
        Task { [weak self] in
            guard let self else { return }
            if let snapshot = await self.store.setFilter(filter) {
                self.snapshotSubject.send(snapshot)
            }
        }
    }

    /// Blocks a user: hides their messages from this feed instantly, persists the block, and
    /// notifies the developer of the offending content (App Store Guideline 1.2 — blocking
    /// must remove content from the feed and report it for review).
    func block(userID: String, login: String, message: ChatMessage? = nil, channelLogin: String? = nil) {
        notifyDeveloperOfBlock(login: login, authorID: userID, message: message, channelLogin: channelLogin)
        guard !userID.isEmpty else {
            noticeSubject.send(SystemNotice(text: String(localized: "Blocked \(login).")))
            return
        }
        Task { [weak self] in
            guard let self else { return }
            await DatabaseManager.shared.setBlockedUser(userID: userID, login: login)
            if let snapshot = await self.store.block(userID) {
                self.snapshotSubject.send(snapshot)
            }
            self.noticeSubject.send(SystemNotice(text: String(localized: "Blocked \(login). Their messages are now hidden.")))
        }
    }

    private func notifyDeveloperOfBlock(login: String, authorID: String?, message: ChatMessage?, channelLogin: String?) {
        let reporter = self.reporter
        let resolvedAuthorID = (message?.author.id).flatMap { $0.isEmpty ? nil : $0 } ?? authorID.flatMap { $0.isEmpty ? nil : $0 }
        Task {
            await reporter.submit(
                WorkerAPI.ReportRequest(
                    channel: channelLogin,
                    messageID: message?.id,
                    authorID: resolvedAuthorID,
                    authorLogin: login,
                    reason: "Blocked abusive user",
                    text: message?.plainText
                )
            )
        }
    }

    /// Flags a message for developer review and immediately hides the author so the
    /// reporter stops seeing their content (App Store Guideline 1.2).
    func report(message: ChatMessage, reason: String, channelLogin: String?) {
        Task { [weak self] in
            guard let self else { return }
            let authorID = message.author.id
            if !authorID.isEmpty {
                await DatabaseManager.shared.setBlockedUser(userID: authorID, login: message.author.login)
                if let snapshot = await self.store.block(authorID) {
                    self.snapshotSubject.send(snapshot)
                }
                self.noticeSubject.send(SystemNotice(text: String(localized: "Reported \(message.author.login). Their messages are now hidden.")))
            } else {
                self.noticeSubject.send(SystemNotice(text: String(localized: "Reported \(message.author.login).")))
            }
            await self.reporter.submit(
                WorkerAPI.ReportRequest(
                    channel: channelLogin,
                    messageID: message.id,
                    authorID: authorID.isEmpty ? nil : authorID,
                    authorLogin: message.author.login,
                    reason: reason,
                    text: message.plainText
                )
            )
        }
    }

    func deleteMessage(messageID: String) {
        moderate(String(localized: "delete the message")) { try await self.room.deleteMessage(messageID) }
    }

    func banUser(userID: String) {
        moderate(String(localized: "ban")) { try await self.room.banUser(userID: userID, duration: nil, reason: nil) }
    }

    func timeoutUser(userID: String, duration: Int) {
        moderate(String(localized: "time out")) { try await self.room.banUser(userID: userID, duration: duration, reason: nil) }
    }

    /// Lets a held message into chat, or keeps it out; it leaves the queue at once and comes back if Twitch refuses.
    func resolveHeld(_ held: HeldMessage, allow: Bool) {
        moderation.held.removeAll { $0.id == held.id }
        moderationSubject.send(moderation)
        Task {
            do {
                try await room.resolveHeldMessage(held.id, allow: allow)
            } catch {
                moderation.held.insert(held, at: 0)
                moderationSubject.send(moderation)
                noticeSubject.send(SystemNotice(text: String(localized: "Couldn't resolve the held message — \(Self.describeCommandError(error))"), isError: true))
            }
        }
    }

    func resolveUnbanRequest(_ request: UnbanRequest, approve: Bool) {
        moderation.requests.removeAll { $0.id == request.id }
        moderationSubject.send(moderation)
        Task {
            do {
                try await room.resolveUnbanRequest(request.id, approve: approve)
            } catch {
                moderation.requests.insert(request, at: 0)
                moderationSubject.send(moderation)
                noticeSubject.send(SystemNotice(text: String(localized: "Couldn't answer the unban request — \(Self.describeCommandError(error))"), isError: true))
            }
        }
    }

    var channelID: String {
        get async { await room.channelID }
    }

    func unbanUser(userID: String) {
        moderate(String(localized: "unban")) { try await self.room.unbanUser(userID: userID) }
    }

    /// What one chatter said while this chat was open, laid out at the width of their card.
    func history(of user: ChatUser, width: CGFloat) async -> [ChatRow] {
        await store.history(of: user, width: width)
    }

    private func moderate(_ label: String, _ op: @escaping () async throws -> Void) {
        Task {
            do { try await op() }
            catch { noticeSubject.send(SystemNotice(text: String(localized: "Couldn't \(label) — \(Self.describeCommandError(error))"), isError: true)) }
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
            noticeSubject.send(SystemNotice(text: String(localized: "Commands: /ban /timeout <sec> /unban /block /unblock <user>")))
            return .handled
        case "ban", "timeout", "unban", "block", "unblock":
            guard let login = targetLogin, !login.isEmpty else {
                noticeSubject.send(SystemNotice(text: String(localized: "Usage: /\(cmd) <user>"), isError: true))
                return .handled
            }
            guard let user = await room.lookupUser(login: login) else {
                noticeSubject.send(SystemNotice(text: String(localized: "User \(login) not found"), isError: true))
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
                noticeSubject.send(SystemNotice(text: String(localized: "Banned \(login)")))
            case "timeout":
                let seconds = args.count > 1 ? (Int(args[1]) ?? 600) : 600
                try await room.banUser(userID: user.id, duration: seconds, reason: nil)
                noticeSubject.send(SystemNotice(text: String(localized: "Timed out \(login) for \(seconds)s")))
            case "unban":
                try await room.unbanUser(userID: user.id)
                noticeSubject.send(SystemNotice(text: String(localized: "Unbanned \(login)")))
            case "block":
                await DatabaseManager.shared.setBlockedUser(userID: user.id, login: user.login)
                if let snapshot = await store.block(user.id) { snapshotSubject.send(snapshot) }
                notifyDeveloperOfBlock(login: user.login, authorID: user.id, message: nil, channelLogin: nil)
                noticeSubject.send(SystemNotice(text: String(localized: "Blocked \(login)")))
            case "unblock":
                await DatabaseManager.shared.removeBlockedUser(userID: user.id)
                noticeSubject.send(SystemNotice(text: String(localized: "Unblocked \(login) · reopen chat to show")))
            default:
                break
            }
        } catch {
            noticeSubject.send(SystemNotice(text: String(localized: "Failed: /\(cmd) \(login) — \(Self.describeCommandError(error))"), isError: true))
        }
    }

    private static func describeCommandError(_ error: Error) -> String {
        guard let api = error as? APIError else { return String(localized: "error") }
        switch api {
        case .unauthorized: return String(localized: "sign in required")
        case .forbidden: return String(localized: "not a moderator here")
        case .rateLimited: return String(localized: "rate limited")
        default: return String(localized: "error")
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

    /// Sends a chat that is already running, as it stands, to a screen that starts showing it: the Chats tab moves
    /// one chat between screens without reconnecting it.
    func replay() {
        if !moderation.isEmpty { moderationSubject.send(moderation) }
        if let lastConnection { connectionSubject.send(lastConnection) }
        if let lastRoomState { roomStateSubject.send(lastRoomState) }
        if let lastCatalog { catalogSubject.send(lastCatalog) }
        Task {
            if let snapshot = await store.replaySnapshot() {
                snapshotSubject.send(snapshot)
            }
        }
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

    func setPlayback(seconds: TimeInterval) {
        Task { await room.setPlayback(seconds: seconds) }
    }

    /// Lays the chat out at a new width. A window being resized or a divider dragged reports many widths while a
    /// layout runs; only the latest of those is laid out next, the ones in between are skipped.
    func updateWidth(_ width: CGFloat) {
        pendingWidth = width
        guard widthTask == nil else { return }
        widthTask = Task { [weak self] in
            guard let self else { return }
            while let width = self.pendingWidth {
                self.pendingWidth = nil
                if let snapshot = await self.store.updateWidth(width) {
                    self.snapshotSubject.send(snapshot)
                }
            }
            self.widthTask = nil
        }
    }

    /// Deletions and timeouts arrive in waves while moderators purge a raid; the chat is redrawn once per wave.
    private func sendModerationSnapshotSoon() {
        guard moderationSnapshotTask == nil else { return }
        moderationSnapshotTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self else { return }
            self.moderationSnapshotTask = nil
            self.snapshotSubject.send(await self.store.snapshot())
        }
    }

    func setReply(parentID: String?) {
        replyParentID = parentID
    }

    /// Sends a message, as a reply when one is set. A reply the viewer switched to while this message travelled stays
    /// set for their next message.
    func send(_ text: String) async throws -> SendResult {
        let parent = replyParentID
        let result = try await room.send(text, replyParentID: parent)
        if result.isSent, replyParentID == parent {
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
            lastCatalog = catalog
            catalogSubject.send(catalog)
        case .messages(let messages):
            if let (snapshot, activity) = await store.append(messages) {
                snapshotSubject.send(snapshot)
                if activity.added > 0 { activitySubject.send(activity) }
            }
        case .backfill(let messages):
            if let snapshot = await store.merge(messages) {
                snapshotSubject.send(snapshot)
            }
        case .delete(let messageID):
            if await store.applyModeration(.deleted, messageID: messageID) != nil {
                sendModerationSnapshotSoon()
            }
        case .clearUser(let userID):
            if await store.clearUser(userID) != nil {
                sendModerationSnapshotSoon()
            }
        case .clearChat:
            if let snapshot = await store.clearChat() {
                snapshotSubject.send(snapshot)
            }
        case .roomState(let state):
            lastRoomState = state
            roomStateSubject.send(state)
        case .connection(let status):
            lastConnection = status
            connectionSubject.send(status)
        case .notice(let notice):
            noticeSubject.send(notice)
        case .moderation(let event):
            await handle(event)
        }
    }

    private static let logCap = 300

    private func handle(_ event: ModerationEvent) async {
        switch event {
        case .held(let held):
            guard !moderation.held.contains(where: { $0.id == held.id }) else { return }
            moderation.held.insert(held, at: 0)
        case .heldResolved(let messageID, _, _):
            moderation.held.removeAll { $0.id == messageID }
        case .unbanRequest(let request):
            guard !moderation.requests.contains(where: { $0.id == request.id }) else { return }
            moderation.requests.insert(request, at: 0)
        case .action(let entry):
            moderation.log.insert(entry, at: 0)
            if moderation.log.count > Self.logCap { moderation.log.removeLast(moderation.log.count - Self.logCap) }
            if entry.action.hasSuffix("unban_request") {
                moderation.requests.removeAll { $0.user.displayName == entry.target || $0.user.login == entry.target?.lowercased() }
            }
            if let (snapshot, _) = await store.append([entry.chatRow(channelID: await room.channelID)]) {
                snapshotSubject.send(snapshot)
            }
        }
        moderationSubject.send(moderation)
    }
}

private actor MessageStore {
    private var rows: [ChatRow] = []
    private var index: [String: Int] = [:]
    private var paused = false
    private var pausedNewCount = 0
    private var frozenRows: [ChatRow] = []
    private var searchQuery = ""
    private var searchMatchIDs: [String] = []
    private var searchScannedThrough: String?
    private var searchLayouts: [String: LaidOutMessage] = [:]
    private var layoutFloor = 0

    private var catalog = EmoteCatalog()
    private var badges = BadgeCatalog()
    private var settings: Settings
    private var layoutKey: ChatLayoutKey
    private var width: CGFloat = 0
    private var layout: MessageLayout?
    private let currentUserLogin: String?
    private var highlighter: ChatHighlighter
    private var blockedUserIDs: Set<String> = []
    private var filter: ContentFilter

    private let capacity = 5000
    private let trimFraction = 0.2
    /// How many of the newest messages the live chat hands the list each batch, enough to fill a tall iPad several times
    /// over; reading back pauses the chat with a deeper window to scroll through.
    private let liveWindow = 200
    private let pausedWindow = 1000
    /// Only this many of the newest messages keep their layout; older ones are laid out again if a search or a
    /// user's history brings them back, so a long session does not hold thousands of attributed strings.
    private var layoutWindow: Int { pausedWindow }
    private let opened = Date().addingTimeInterval(-5)

    init(settings: Settings, currentUserLogin: String?, filter: ContentFilter) {
        self.settings = settings
        self.layoutKey = settings.chatLayoutKey
        self.currentUserLogin = currentUserLogin
        self.filter = filter
        self.highlighter = settings.makeHighlighter(login: currentUserLogin)
    }

    /// Lays every message out again when something chat layout depends on changed.
    func updateSettings(_ settings: Settings) -> ChatSnapshot? {
        let key = settings.chatLayoutKey
        guard key != layoutKey else { return nil }
        self.settings = settings
        highlighter = settings.makeHighlighter(login: currentUserLogin)
        layoutKey = key
        rebuildLayout()
        guard !rows.isEmpty else { return nil }
        let current = currentSnapshot()
        return ChatSnapshot(rows: current.rows, isPaused: current.isPaused, newCount: current.newCount, relayout: true)
    }

    /// Applies an updated content filter, dropping any buffered messages that now match so
    /// the change takes effect on already-received chat, not just future messages.
    func setFilter(_ filter: ContentFilter) -> ChatSnapshot? {
        guard filter != self.filter else { return nil }
        self.filter = filter
        guard !filter.isEmpty else { return nil }
        let before = rows.count
        rows.removeAll { filter.shouldHide($0.message.plainText) }
        frozenRows.removeAll { filter.shouldHide($0.message.plainText) }
        guard rows.count != before else { return nil }
        rebuildIndex()
        layOutWindow()
        return currentSnapshot()
    }

    func updateWidth(_ width: CGFloat) -> ChatSnapshot? {
        guard width > 0, width != self.width else { return nil }
        self.width = width
        rebuildLayout()
        guard !rows.isEmpty else { return nil }
        let current = currentSnapshot()
        return ChatSnapshot(rows: current.rows, isPaused: current.isPaused, newCount: current.newCount, relayout: true)
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
            searchQuery = ""
            searchLayouts = [:]
            return liveSnapshot()
        }
        frozenRows = Array(rows.suffix(pausedWindow))
        return frozenSnapshot()
    }

    func setBlocked(_ ids: Set<String>) -> ChatSnapshot? {
        let ids = ids.filter { !$0.isEmpty }
        blockedUserIDs = ids
        guard !ids.isEmpty else { return nil }
        let before = rows.count
        rows.removeAll { ids.contains($0.message.author.id) }
        frozenRows.removeAll { ids.contains($0.message.author.id) }
        guard rows.count != before else { return nil }
        rebuildIndex()
        layOutWindow()
        return currentSnapshot()
    }

    func block(_ userID: String) -> ChatSnapshot? {
        guard !userID.isEmpty else { return nil }
        blockedUserIDs.insert(userID)
        let before = rows.count
        rows.removeAll { $0.message.author.id == userID }
        frozenRows.removeAll { $0.message.author.id == userID }
        if rows.count != before {
            rebuildIndex()
            layOutWindow()
        }
        return currentSnapshot()
    }

    private func isSuppressed(_ message: ChatMessage) -> Bool {
        if !message.author.id.isEmpty && blockedUserIDs.contains(message.author.id) { return true }
        return filter.shouldHide(message.plainText)
    }

    func append(_ messages: [ChatMessage]) -> (ChatSnapshot, ChatActivity)? {
        guard !messages.isEmpty else { return nil }
        var added = 0
        var highlights: [ChatRow] = []
        for message in messages {
            if isSuppressed(message) { continue }
            let row = makeRow(message)
            if let existing = index[message.id] {
                rows[existing] = row
            } else {
                index[message.id] = rows.count
                rows.append(row)
                if message.timestamp >= opened {
                    added += 1
                    let reason = row.laidOut.map(\.highlight) ?? highlighter.reason(for: message)
                    if reason != nil { highlights.append(row) }
                }
            }
        }
        trimIfNeeded()
        releaseOldLayouts()
        let snapshot: ChatSnapshot
        if paused {
            pausedNewCount += added
            snapshot = frozenSnapshot()
        } else {
            snapshot = liveSnapshot()
        }
        let activity = ChatActivity(added: added, highlights: highlights)
        return (ChatSnapshot(rows: snapshot.rows, isPaused: snapshot.isPaused, newCount: snapshot.newCount, alerts: highlights.count), activity)
    }

    /// The chat as it stands now.
    func snapshot() -> ChatSnapshot {
        currentSnapshot()
    }

    /// The chat as it stands, for a screen that starts showing it; nil until anything arrived.
    func replaySnapshot() -> ChatSnapshot? {
        guard !rows.isEmpty else { return nil }
        let current = currentSnapshot()
        return ChatSnapshot(rows: current.rows, isPaused: current.isPaused, newCount: current.newCount, relayout: true)
    }

    /// Merges gap-backfill messages after a reconnect: skips ids already buffered and anything
    /// older than the newest buffered row (so trimmed history is never resurrected), then splices
    /// the remainder into the tail in timestamp order without disturbing existing rows.
    func merge(_ messages: [ChatMessage]) -> ChatSnapshot? {
        let cutoff = rows.last?.message.timestamp ?? .distantPast
        let missed = messages
            .filter { $0.timestamp >= cutoff && index[$0.id] == nil && !isSuppressed($0) }
            .sorted { $0.timestamp < $1.timestamp }
        guard !missed.isEmpty else { return nil }
        spliceAtTail(missed)
        trimIfNeeded()
        rebuildIndex()
        if paused {
            pausedNewCount += missed.count
            return frozenSnapshot()
        }
        return liveSnapshot()
    }

    /// Merge-appends timestamp-sorted backfill rows at the buffer tail, keeping existing
    /// equal-timestamp rows in place ahead of the inserted ones.
    private func spliceAtTail(_ missed: [ChatMessage]) {
        var splice = rows.count
        while splice > 0, rows[splice - 1].message.timestamp > missed[0].timestamp {
            splice -= 1
        }
        let tail = Array(rows[splice...])
        rows.removeSubrange(splice...)
        var pending = missed[...]
        for row in tail {
            while let next = pending.first, next.timestamp < row.message.timestamp {
                rows.append(makeRow(next))
                pending.removeFirst()
            }
            rows.append(row)
        }
        rows.append(contentsOf: pending.map(makeRow))
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

    func history(of user: ChatUser, width: CGFloat) -> [ChatRow] {
        guard width > 0 else { return [] }
        let layout = MessageLayout(width: width, settings: settings, catalog: catalog, badges: badges, currentUserLogin: currentUserLogin)
        let login = user.login.lowercased()
        return rows
            .filter { user.id.isEmpty ? $0.message.author.login.lowercased() == login : $0.message.author.id == user.id }
            .suffix(200)
            .map { ChatRow(message: $0.message, laidOut: layout.layout($0.message)) }
    }

    /// Narrows the paused chat to messages matching the query, and keeps it narrowed while new messages arrive; an
    /// empty query goes back to the chat as it was paused.
    func search(_ query: String) -> ChatSnapshot {
        searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        searchMatchIDs = []
        searchScannedThrough = nil
        searchLayouts = [:]
        return currentSnapshot()
    }

    /// The messages matching the query. Each message is checked once: later calls only look at what arrived since,
    /// and drop matches that were trimmed or blocked away.
    private func searchMatches() -> [ChatRow] {
        let start: Int
        if let last = searchScannedThrough, let position = index[last] {
            start = position + 1
        } else {
            start = 0
            searchMatchIDs = []
        }
        if start < rows.count {
            for row in rows[start...] where matchesSearch(row) { searchMatchIDs.append(row.id) }
        }
        searchScannedThrough = rows.last?.id
        searchMatchIDs.removeAll { index[$0] == nil }
        return searchMatchIDs.compactMap { id in index[id].map { withLayout(rows[$0]) } }
    }

    private func matchesSearch(_ row: ChatRow) -> Bool {
        row.message.author.displayName.lowercased().contains(searchQuery)
            || row.message.author.login.lowercased().contains(searchQuery)
            || row.message.plainText.lowercased().contains(searchQuery)
    }

    /// A row ready to draw: older rows that gave up their layout get one again, kept for as long as the search that
    /// found them, so new batches arriving under a search do not lay the same matches out again.
    private func withLayout(_ row: ChatRow) -> ChatRow {
        guard row.laidOut == nil, let layout else { return row }
        if let cached = searchLayouts[row.id] { return ChatRow(message: row.message, laidOut: cached) }
        let laidOut = layout.layout(row.message)
        searchLayouts[row.id] = laidOut
        return ChatRow(message: row.message, laidOut: laidOut)
    }

    /// Frees the layouts of messages that slid out of the window the chat can show without a search.
    private func releaseOldLayouts() {
        let target = max(0, rows.count - layoutWindow)
        guard target > layoutFloor else { return }
        for position in layoutFloor..<target { rows[position].laidOut = nil }
        layoutFloor = target
    }

    /// Lays out any message inside the window that has no layout, as after blocked messages were removed and older
    /// ones moved into it.
    private func layOutWindow() {
        guard let layout else { return }
        let start = max(0, rows.count - layoutWindow)
        layoutFloor = start
        for position in start..<rows.count where rows[position].laidOut == nil {
            rows[position].laidOut = layout.layout(rows[position].message)
        }
    }

    private func makeRow(_ message: ChatMessage) -> ChatRow {
        guard let layout else { return ChatRow(message: message) }
        return ChatRow(message: message, laidOut: layout.layout(message))
    }

    private func rebuildLayout() {
        guard width > 0 else { return }
        layout = MessageLayout(width: width, settings: settings, catalog: catalog, badges: badges, currentUserLogin: currentUserLogin)
        searchLayouts = [:]
        let start = max(0, rows.count - layoutWindow)
        for position in rows.indices {
            rows[position].laidOut = position >= start ? layout?.layout(rows[position].message) : nil
        }
        layoutFloor = start
        for position in frozenRows.indices {
            frozenRows[position] = ChatRow(message: frozenRows[position].message, laidOut: layout?.layout(frozenRows[position].message))
        }
    }

    private func trimIfNeeded() {
        guard rows.count > capacity else { return }
        let drop = Int(Double(capacity) * trimFraction)
        rows.removeFirst(drop)
        layoutFloor = max(0, layoutFloor - drop)
        rebuildIndex()
    }

    private func rebuildIndex() {
        index.removeAll(keepingCapacity: true)
        for (position, row) in rows.enumerated() {
            index[row.message.id] = position
        }
    }

    private func currentSnapshot() -> ChatSnapshot {
        if !searchQuery.isEmpty {
            return ChatSnapshot(rows: searchMatches(), isPaused: true, newCount: pausedNewCount)
        }
        return paused ? frozenSnapshot() : liveSnapshot()
    }

    private func liveSnapshot() -> ChatSnapshot {
        let window = rows.suffix(liveWindow)
        return ChatSnapshot(rows: Array(window), isPaused: false, newCount: 0)
    }

    private func frozenSnapshot() -> ChatSnapshot {
        guard searchQuery.isEmpty else { return ChatSnapshot(rows: searchMatches(), isPaused: true, newCount: pausedNewCount) }
        return ChatSnapshot(rows: frozenRows, isPaused: true, newCount: pausedNewCount)
    }
}
