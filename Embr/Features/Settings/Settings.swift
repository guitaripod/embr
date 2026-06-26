import Foundation
import EmbrCore

nonisolated struct Settings: Codable, Sendable, Equatable {
    enum ThemePreference: String, Codable, Sendable, Equatable, CaseIterable {
        case system
        case light
        case dark
    }

    var theme: ThemePreference

    var showTimestamps: Bool
    var compactChat: Bool
    var messageScale: Double
    var fontSizeDelta: Int
    var highlightMentions: Bool
    var recentMessagesBackfill: Bool

    var animateEmotes: Bool
    var showThirdPartyEmotes: [EmoteProvider: Bool]

    var autoplay: Bool
    var chatDelaySeconds: Double
    var autoSyncChatDelay: Bool
    var keepScreenAwake: Bool

    var openLinksInApp: Bool
    var hapticsEnabled: Bool

    var chatOnly: Bool?
    var backgroundAudio: Bool?

    static let `default` = Settings(
        theme: .system,
        showTimestamps: false,
        compactChat: false,
        messageScale: 1.0,
        fontSizeDelta: 0,
        highlightMentions: true,
        recentMessagesBackfill: true,
        animateEmotes: true,
        showThirdPartyEmotes: [
            .sevenTV: true,
            .betterTTV: true,
            .frankerFaceZ: true
        ],
        autoplay: true,
        chatDelaySeconds: 0,
        autoSyncChatDelay: true,
        keepScreenAwake: true,
        openLinksInApp: true,
        hapticsEnabled: true,
        chatOnly: false,
        backgroundAudio: true
    )

    func thirdPartyEmotesEnabled(_ provider: EmoteProvider) -> Bool {
        showThirdPartyEmotes[provider] ?? true
    }
}
