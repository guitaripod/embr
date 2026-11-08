import Foundation
import EmbrCore

/// Clips the viewer reported. A reported clip leaves the feed at once and stays out of every clip list on this device,
/// the same way a reported chatter's messages stay hidden.
struct HiddenClips {
    private static let key = "clips.hidden"
    private static let capacity = 500

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var ids: Set<String> {
        Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    func hide(_ clipID: String) {
        var list = defaults.stringArray(forKey: Self.key) ?? []
        guard !list.contains(clipID) else { return }
        list.append(clipID)
        defaults.set(Array(list.suffix(Self.capacity)), forKey: Self.key)
    }

    func visible(_ clips: [Clip]) -> [Clip] {
        let hidden = ids
        guard !hidden.isEmpty else { return clips }
        return clips.filter { !hidden.contains($0.id) }
    }
}
