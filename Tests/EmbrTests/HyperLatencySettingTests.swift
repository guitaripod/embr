import Foundation
import Testing
import EmbrCore

@testable import Embr

@MainActor
@Suite struct HyperLatencySettingTests {
    private func freshDefaults() -> UserDefaults {
        let name = "HyperLatencySettingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aBlobSavedBeforeHyperExistedKeepsEverySettingAndLeavesHyperOff() throws {
        var older = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings.default)) as? [String: Any] ?? [:]
        older.removeValue(forKey: "hyperLowLatency")
        older["keepScreenAwake"] = false
        let defaults = freshDefaults()
        defaults.set(try JSONSerialization.data(withJSONObject: older), forKey: "settings")

        let store = SettingsStore(defaults: defaults)

        #expect(store.current.keepScreenAwake == false)
        #expect(store.current.hyperLowLatencyEnabled == false)
        #expect(store.current.liveLatency == .standard)
    }

    @Test func turningHyperOnIsWhatLiveStreamsResolveWithAndItIsSaved() {
        let defaults = freshDefaults()
        let store = SettingsStore(defaults: defaults)
        store.update { $0.hyperLowLatency = true }
        #expect(store.current.liveLatency == .hyper)
        store.flush()
        #expect(SettingsStore(defaults: defaults).current.liveLatency == .hyper)
    }

    @Test func aBadgedRowRedrawsWhenItsBadgeChanges() {
        let plain = SettingsItem(id: "h", title: "Hyper Low Latency", kind: .toggle(isOn: false) { _ in })
        let badged = SettingsItem(id: "h", title: "Hyper Low Latency", badge: SettingsBadge(style: .experimental) { _ in }, kind: .toggle(isOn: false) { _ in })
        #expect(plain.signature != badged.signature)
    }
}
