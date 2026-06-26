import EmbrCore

/// Single chokepoint for recording an emote as "recently used" so the picker and
/// keyboard can surface a Recent section.
enum EmoteUsage {
    static func record(_ emote: Emote) {
        let name = emote.name
        let provider = emote.provider.rawValue
        Task { await DatabaseManager.shared.bumpRecentEmote(name: name, provider: provider) }
    }
}
