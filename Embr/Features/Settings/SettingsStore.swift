import Foundation
import Combine
import EmbrCore

@MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    let changes = PassthroughSubject<Settings, Never>()

    private(set) var current: Settings

    private let defaults: UserDefaults
    private let key = "settings"
    private let logger = AppLogger.shared
    private var pendingWrite: DispatchWorkItem?
    private let writeDelay: TimeInterval = 0.5

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.current = Self.load(from: defaults, key: "settings")
    }

    func update(_ mutate: (inout Settings) -> Void) {
        var next = current
        mutate(&next)
        guard next != current else { return }
        current = next
        changes.send(next)
        schedulePersist(next)
    }

    private func schedulePersist(_ settings: Settings) {
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persist(settings)
        }
        pendingWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + writeDelay, execute: work)
    }

    private func persist(_ settings: Settings) {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: key)
        } catch {
            logger.error("failed to persist settings: \(error)", category: .persistence)
        }
    }

    private static func load(from defaults: UserDefaults, key: String) -> Settings {
        guard let data = defaults.data(forKey: key) else { return .default }
        do {
            return try JSONDecoder().decode(Settings.self, from: data)
        } catch {
            AppLogger.shared.warn("failed to decode settings, using defaults: \(error)", category: .persistence)
            return .default
        }
    }
}
