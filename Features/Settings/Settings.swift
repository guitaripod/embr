import Foundation
import EmbrCore

nonisolated struct Settings: Codable, Sendable, Equatable {
    enum ThemePreference: String, Codable, Sendable, Equatable, CaseIterable {
        case system
        case light
        case dark
    }

    enum StartTab: String, Codable, Sendable, Equatable, CaseIterable {
        case following
        case favorites
        case top
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
    var showsRecentlyWatched: Bool?
    var favoritesOnlyTop: Bool?
    var startTab: StartTab?

    var filterObjectionableContent: Bool?
    var mutedKeywords: [String]?

    var highlightWords: [String]?
    var highlightUsers: [String]?
    var highlightSound: Bool?
    var highlightHaptic: Bool?
    var moderatorTools: Bool?

    var accent: String?
    var palette: String?
    var chatFont: String?
    var supporterNameEffects: Bool?

    var tvChatVisible: Bool?
    var tvChatPlacement: ChatPlacement?
    var tvChatTextSize: ChatTextSize?
    var livePreviews: Bool?

    enum ChatPlacement: String, Codable, Sendable, Equatable, CaseIterable {
        case right
        case left
    }

    enum ChatTextSize: String, Codable, Sendable, Equatable, CaseIterable {
        case small
        case medium
        case large
        case extraLarge
    }

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
        showsRecentlyWatched: true,
        favoritesOnlyTop: false,
        startTab: .following,
        filterObjectionableContent: true,
        mutedKeywords: []
    )

    func thirdPartyEmotesEnabled(_ provider: EmoteProvider) -> Bool {
        showThirdPartyEmotes[provider] ?? true
    }

    var showsRecentlyWatchedEnabled: Bool {
        showsRecentlyWatched ?? true
    }

    var favoritesOnlyTopEnabled: Bool {
        favoritesOnlyTop ?? false
    }

    var startTabPreference: StartTab {
        startTab ?? .following
    }

    var objectionableFilterEnabled: Bool {
        filterObjectionableContent ?? true
    }

    var mutedKeywordList: [String] {
        mutedKeywords ?? []
    }

    var highlightWordList: [String] {
        highlightWords ?? []
    }

    var highlightUserList: [String] {
        highlightUsers ?? []
    }

    var highlightSoundEnabled: Bool {
        highlightSound ?? false
    }

    var highlightHapticEnabled: Bool {
        highlightHaptic ?? true
    }

    var moderatorToolsEnabled: Bool {
        moderatorTools ?? false
    }

    /// What stands out in chat for the signed-in viewer: mentions of them, their chosen words and their chosen users.
    func makeHighlighter(login: String?) -> ChatHighlighter {
        ChatHighlighter(login: login, mentions: highlightMentions, words: highlightWordList, users: highlightUserList)
    }

    var tvChatVisibleEnabled: Bool {
        tvChatVisible ?? true
    }

    var tvChatPlacementPreference: ChatPlacement {
        tvChatPlacement ?? .right
    }

    var tvChatTextSizePreference: ChatTextSize {
        tvChatTextSize ?? .medium
    }

    var livePreviewsEnabled: Bool {
        livePreviews ?? true
    }

    /// Whether supporters' names show in their flame color and glow, as each supporter picked. Off, every name keeps
    /// its Twitch color; the badges stay.
    var supporterNameEffectsEnabled: Bool {
        supporterNameEffects ?? true
    }

    var supporterTheme: SupporterTheme {
        palette.flatMap(SupporterTheme.init(rawValue:)) ?? .standard
    }

    var supporterChatFont: SupporterChatFont {
        chatFont.flatMap(SupporterChatFont.init(rawValue:)) ?? .standard
    }

    /// The content filter derived from current settings. The severe-slur list is active
    /// whenever the objectionable-content toggle is on; the user's muted keywords always
    /// apply on top.
    func makeContentFilter() -> ContentFilter {
        ContentFilter(userTerms: mutedKeywordList, includeDefaultList: objectionableFilterEnabled)
    }
}
