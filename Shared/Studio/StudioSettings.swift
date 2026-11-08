import Combine
import Foundation
import EmbrCore

/// Studio's own settings, apart from the viewer app's, so a missing field from an older version falls back to its
/// default instead of resetting everything.
struct StudioSettings: Codable, Equatable, Sendable {
    var role: StudioRole = .broadcaster
    var moderatedChannelID: String?
    var moderatedChannelLogin: String?
    var moderatedChannelName: String?
    var chatOnRight = false
    var chatOnly = false
    var showsViewers = true
    var stayAwakeWhileLive = true
    var stayAwakeWhileOffline = false
    var burnInProtection = true
    var adWarnings = true
    var defaultAdLength = 90
    var announcesAds = false
    var micHearsTV: Bool?
    var alerts = AlertPreferences()
    var soundVolume: Float = 0.7

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = StudioSettings()
        role = (try? container.decodeIfPresent(StudioRole.self, forKey: .role)) ?? defaults.role
        moderatedChannelID = try? container.decodeIfPresent(String.self, forKey: .moderatedChannelID)
        moderatedChannelLogin = try? container.decodeIfPresent(String.self, forKey: .moderatedChannelLogin)
        moderatedChannelName = try? container.decodeIfPresent(String.self, forKey: .moderatedChannelName)
        chatOnRight = (try? container.decodeIfPresent(Bool.self, forKey: .chatOnRight)) ?? defaults.chatOnRight
        chatOnly = (try? container.decodeIfPresent(Bool.self, forKey: .chatOnly)) ?? defaults.chatOnly
        showsViewers = (try? container.decodeIfPresent(Bool.self, forKey: .showsViewers)) ?? defaults.showsViewers
        stayAwakeWhileLive = (try? container.decodeIfPresent(Bool.self, forKey: .stayAwakeWhileLive)) ?? defaults.stayAwakeWhileLive
        stayAwakeWhileOffline = (try? container.decodeIfPresent(Bool.self, forKey: .stayAwakeWhileOffline)) ?? defaults.stayAwakeWhileOffline
        burnInProtection = (try? container.decodeIfPresent(Bool.self, forKey: .burnInProtection)) ?? defaults.burnInProtection
        adWarnings = (try? container.decodeIfPresent(Bool.self, forKey: .adWarnings)) ?? defaults.adWarnings
        defaultAdLength = (try? container.decodeIfPresent(Int.self, forKey: .defaultAdLength)) ?? defaults.defaultAdLength
        announcesAds = (try? container.decodeIfPresent(Bool.self, forKey: .announcesAds)) ?? defaults.announcesAds
        micHearsTV = try? container.decodeIfPresent(Bool.self, forKey: .micHearsTV)
        alerts = (try? container.decodeIfPresent(AlertPreferences.self, forKey: .alerts)) ?? defaults.alerts
        soundVolume = (try? container.decodeIfPresent(Float.self, forKey: .soundVolume)) ?? defaults.soundVolume
    }

    /// The alert preferences the queue works with: the ad warning sound follows its own switch.
    var effectiveAlerts: AlertPreferences {
        var preferences = alerts
        if !adWarnings { preferences.sounds.remove(.adWarning) }
        return preferences
    }
}

/// Keeps Studio's settings on this device, and the quick messages in iCloud so they are written once on the iPhone and
/// used on the Apple TV.
@MainActor
final class StudioSettingsStore {
    static let shared = StudioSettingsStore()

    let changes = PassthroughSubject<StudioSettings, Never>()
    private(set) var current: StudioSettings
    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore?
    private var cloudObserver: NSObjectProtocol?

    private static let key = "studio.settings"
    private static let quickMessagesKey = "studio.quickMessages"
    static let quickMessageLimit = 6

    init(defaults: UserDefaults = .standard, cloud: NSUbiquitousKeyValueStore? = .default) {
        self.defaults = defaults
        self.cloud = cloud
        current = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(StudioSettings.self, from: $0) } ?? StudioSettings()
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.changes.send(self?.current ?? StudioSettings()) }
        }
    }

    func update(_ change: (inout StudioSettings) -> Void) {
        var next = current
        change(&next)
        guard next != current else { return }
        current = next
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: Self.key) }
        changes.send(next)
    }

    /// The streamer's quick messages: what Studio can post to chat in one press, such as a note before an ad break.
    var quickMessages: [String] {
        let stored = (cloud?.array(forKey: Self.quickMessagesKey) as? [String]) ?? defaults.stringArray(forKey: Self.quickMessagesKey)
        guard let stored, !stored.isEmpty else { return Self.defaultQuickMessages }
        return stored
    }

    func setQuickMessages(_ messages: [String]) {
        let cleaned = messages.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(Self.quickMessageLimit)
        let list = Array(cleaned)
        defaults.set(list, forKey: Self.quickMessagesKey)
        cloud?.set(list, forKey: Self.quickMessagesKey)
        cloud?.synchronize()
        changes.send(current)
    }

    static var defaultQuickMessages: [String] {
        [
            String(localized: "Ad break in a minute, back in 90 seconds!", comment: "Default Studio quick message"),
            String(localized: "Quick break, back in 5 minutes!", comment: "Default Studio quick message"),
            String(localized: "Welcome in, raiders! 👋", comment: "Default Studio quick message"),
            String(localized: "Thanks for all the support tonight 💛", comment: "Default Studio quick message"),
        ]
    }
}
