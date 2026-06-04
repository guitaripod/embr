import Foundation
import Combine
import EmbrCore

struct WatchedChannel: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let login: String
    let name: String

    var displayName: String { name.isEmpty ? login : name }
}

@MainActor
final class WatchHistoryStore {
    static let shared = WatchHistoryStore()

    let changes = PassthroughSubject<[WatchedChannel], Never>()

    private(set) var recent: [WatchedChannel]

    private let defaults: UserDefaults
    private let key = "watchHistory"
    private let limit = 20

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.recent = Self.load(from: defaults, key: "watchHistory")
    }

    func record(id: String, login: String, name: String) {
        guard !id.isEmpty, !login.isEmpty else { return }
        let entry = WatchedChannel(id: id, login: login, name: name)
        var next = recent.filter { $0.id != id }
        next.insert(entry, at: 0)
        if next.count > limit { next = Array(next.prefix(limit)) }
        guard next != recent else { return }
        recent = next
        changes.send(next)
        persist(next)
    }

    func clear() {
        guard !recent.isEmpty else { return }
        recent = []
        changes.send([])
        persist([])
    }

    private func persist(_ entries: [WatchedChannel]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [WatchedChannel] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WatchedChannel].self, from: data) else { return [] }
        return decoded
    }
}
