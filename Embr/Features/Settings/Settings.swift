import Foundation
import EmbrCore

nonisolated struct Settings: Codable, Sendable, Equatable {
    enum ThemePreference: String, Codable, Sendable, Equatable, CaseIterable {
        case system
        case light
        case dark
    }

    var theme: ThemePreference
    var accentUsesTwitchPurple: Bool

    var showTimestamps: Bool
    var compactChat: Bool
    var messageScale: Double
    var fontSizeDelta: Int
    var showDeletedMessages: Bool
    var highlightMentions: Bool
    var recentMessagesBackfill: Bool

    var animateEmotes: Bool
    var showThirdPartyEmotes: [EmoteProvider: Bool]

    var defaultQuality: String
    var defaultToHighest: Bool
    var autoplay: Bool
    var chatDelaySeconds: Double
    var autoSyncChatDelay: Bool
    var keepScreenAwake: Bool

    var openLinksInApp: Bool
    var hapticsEnabled: Bool
    var shareCrashLogs: Bool

    var chatOnly: Bool?

    static let `default` = Settings(
        theme: .system,
        accentUsesTwitchPurple: true,
        showTimestamps: false,
        compactChat: false,
        messageScale: 1.0,
        fontSizeDelta: 0,
        showDeletedMessages: false,
        highlightMentions: true,
        recentMessagesBackfill: true,
        animateEmotes: true,
        showThirdPartyEmotes: [
            .sevenTV: true,
            .betterTTV: true,
            .frankerFaceZ: true
        ],
        defaultQuality: "auto",
        defaultToHighest: false,
        autoplay: true,
        chatDelaySeconds: 0,
        autoSyncChatDelay: true,
        keepScreenAwake: true,
        openLinksInApp: true,
        hapticsEnabled: true,
        shareCrashLogs: false,
        chatOnly: false
    )

    func thirdPartyEmotesEnabled(_ provider: EmoteProvider) -> Bool {
        showThirdPartyEmotes[provider] ?? true
    }
}
