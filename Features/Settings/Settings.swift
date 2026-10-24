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

    var filterObjectionableContent: Bool?
    var mutedKeywords: [String]?

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
        backgroundAudio: true,
        filterObjectionableContent: true,
        mutedKeywords: []
    )

    func thirdPartyEmotesEnabled(_ provider: EmoteProvider) -> Bool {
        showThirdPartyEmotes[provider] ?? true
    }

    var objectionableFilterEnabled: Bool {
        filterObjectionableContent ?? true
    }

    var mutedKeywordList: [String] {
        mutedKeywords ?? []
    }

    /// The content filter derived from current settings. The severe-slur list is active
    /// whenever the objectionable-content toggle is on; the user's muted keywords always
    /// apply on top.
    func makeContentFilter() -> ContentFilter {
        ContentFilter(userTerms: mutedKeywordList, includeDefaultList: objectionableFilterEnabled)
    }
}
