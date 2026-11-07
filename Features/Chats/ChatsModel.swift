import Foundation
import Combine
import EmbrCore
import MidgarCore

/// The chats kept open in the Chats tab. It remembers which channels they are and in what order across launches; once
/// the tab has opened, each chat stays connected (all of them on one EventSub connection) and counts what arrives while
/// it is out of sight. Messages that stand out for the viewer in any of them gather in Mentions.
@MainActor
final class ChatsModel {
    static let shared = ChatsModel()

    struct Entry: Codable, Hashable, Sendable {
        let id: String
        let login: String
        let name: String

        var channel: ChannelInfo {
            ChannelInfo(id: id, broadcasterLogin: login, broadcasterName: name, gameID: "", gameName: "", title: "", language: "", tags: [], isLive: false)
        }
    }

    /// A message that stood out for the viewer in one of the open chats.
    struct Mention: Hashable {
        let channel: Entry
        let row: ChatRow
        let arrived: Date

        static func == (lhs: Mention, rhs: Mention) -> Bool { lhs.row.id == rhs.row.id }
        func hash(into hasher: inout Hasher) { hasher.combine(row.id) }
    }

    /// One open chat while the tab is active: its running chat and what arrived since the viewer last looked.
    final class Session {
        let entry: Entry
        let viewModel: ChatViewModel
        let viewer: AuthenticatedUser?
        fileprivate(set) var unread = 0
        fileprivate(set) var highlights = 0
        fileprivate var cancellables = Set<AnyCancellable>()

        fileprivate init(entry: Entry, viewModel: ChatViewModel, viewer: AuthenticatedUser?) {
            self.entry = entry
            self.viewModel = viewModel
            self.viewer = viewer
        }
    }

    let changes = PassthroughSubject<Void, Never>()
    private(set) var entries: [Entry]
    private(set) var selectedID: String?
    private(set) var mentions: [Mention] = []
    private(set) var unseenMentions = 0

    private let defaults: UserDefaults
    private let auth: AuthService
    private var sessions: [String: Session] = [:]
    private var visible: Set<String> = []
    private var viewer: AuthenticatedUser?
    private var isActive = false
    private var cancellables = Set<AnyCancellable>()

    private static let entriesKey = "chats.open"
    private static let selectedKey = "chats.selected"
    private static let mentionCap = 300

    init(defaults: UserDefaults = .standard, auth: AuthService = .shared) {
        self.defaults = defaults
        self.auth = auth
        self.entries = (defaults.data(forKey: Self.entriesKey)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        self.selectedID = defaults.string(forKey: Self.selectedKey) ?? entries.first?.id
        auth.statePublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.restartForNewViewer() }
            .store(in: &cancellables)
    }

    var selected: Entry? {
        entries.first { $0.id == selectedID } ?? entries.first
    }

    func session(for id: String) -> Session? {
        sessions[id]
    }

    func contains(_ id: String) -> Bool {
        entries.contains { $0.id == id }
    }

    /// Connects every open chat; the tab calls it the first time it shows.
    func activate() async {
        guard !isActive else { return }
        isActive = true
        viewer = await auth.currentUser()
        for entry in entries { startSession(entry) }
        changes.send()
    }

    /// Adds a channel's chat, or brings it to the front when it is already open.
    func open(_ entry: Entry) {
        if !contains(entry.id) {
            entries.append(entry)
            if isActive { startSession(entry) }
            persist()
            MidgarLog.info("chats: opened \(entry.login) (\(entries.count) open)", category: .chat)
        }
        select(entry.id)
    }

    func close(_ id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.remove(at: index)
        sessions.removeValue(forKey: id)?.viewModel.stop()
        visible.remove(id)
        if selectedID == id {
            selectedID = entries.indices.contains(index) ? entries[index].id : entries.last?.id
        }
        persist()
        MidgarLog.info("chats: closed \(id) (\(entries.count) open)", category: .chat)
        changes.send()
    }

    func move(from source: Int, to destination: Int) {
        guard entries.indices.contains(source), entries.indices.contains(destination), source != destination else { return }
        let entry = entries.remove(at: source)
        entries.insert(entry, at: destination)
        persist()
        changes.send()
    }

    func select(_ id: String) {
        guard contains(id) else { return }
        selectedID = id
        persist()
        changes.send()
    }

    /// The chats on screen right now: their counts reset and stay at zero while they show. It reports a change only
    /// when something changed, since the tab calls it each time it lays out.
    func setVisible(_ ids: Set<String>) {
        var changed = visible != ids
        visible = ids
        for id in ids {
            guard let session = sessions[id], session.unread != 0 || session.highlights != 0 else { continue }
            session.unread = 0
            session.highlights = 0
            changed = true
        }
        if changed { changes.send() }
    }

    func markMentionsSeen() {
        guard unseenMentions != 0 else { return }
        unseenMentions = 0
        changes.send()
    }

    func clearMentions() {
        mentions.removeAll()
        unseenMentions = 0
        changes.send()
    }

    #if DEBUG
    /// Opens the given chats in memory only, for screenshots of the invented world.
    func seedForScreenshots(_ seeded: [Entry]) {
        for session in sessions.values { session.viewModel.stop() }
        sessions.removeAll()
        entries = seeded
        selectedID = seeded.first?.id
        if isActive { for entry in entries { startSession(entry) } }
        changes.send()
    }
    #endif

    private func startSession(_ entry: Entry) {
        guard sessions[entry.id] == nil else { return }
        let room = AppContainer.shared.makeChatRoom(channel: entry.channel, loggedIn: viewer != nil)
        let viewModel = ChatViewModel(room: room, currentUserLogin: viewer?.login)
        let session = Session(entry: entry, viewModel: viewModel, viewer: viewer)
        viewModel.activitySubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak session] activity in
                guard let self, let session else { return }
                self.record(activity, in: session)
            }
            .store(in: &session.cancellables)
        sessions[entry.id] = session
        viewModel.start()
    }

    private func record(_ activity: ChatActivity, in session: Session) {
        let onScreen = visible.contains(session.entry.id)
        let highlights = newMentions(in: activity)
        if !onScreen {
            session.unread += activity.added
            session.highlights += highlights.count
        }
        if !highlights.isEmpty {
            let now = Date()
            mentions.insert(contentsOf: highlights.reversed().map { Mention(channel: session.entry, row: $0, arrived: now) }, at: 0)
            if mentions.count > Self.mentionCap { mentions.removeLast(mentions.count - Self.mentionCap) }
            if !onScreen { unseenMentions += highlights.count }
        }
        changes.send()
    }

    /// The activity's highlighted messages that Mentions does not hold yet; a chat closed and opened again loads its
    /// recent messages a second time.
    private func newMentions(in activity: ChatActivity) -> [ChatRow] {
        guard !activity.highlights.isEmpty else { return [] }
        let known = Set(mentions.map(\.row.id))
        return activity.highlights.filter { !known.contains($0.id) }
    }

    /// Signing in or out changes how every chat connects and who it highlights, so the open chats start over.
    private func restartForNewViewer() {
        guard isActive else { return }
        Task { [weak self] in
            guard let self else { return }
            let user = await self.auth.currentUser()
            guard user?.id != self.viewer?.id else { return }
            self.viewer = user
            for session in self.sessions.values { session.viewModel.stop() }
            self.sessions.removeAll()
            for entry in self.entries { self.startSession(entry) }
            self.changes.send()
        }
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(entries), forKey: Self.entriesKey)
        defaults.set(selectedID, forKey: Self.selectedKey)
    }
}
