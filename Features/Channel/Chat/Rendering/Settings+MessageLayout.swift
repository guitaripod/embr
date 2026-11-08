import UIKit
import EmbrCore

extension Settings: MessageLayoutSettings {
    private static let baseFontSize: CGFloat = 14

    var chatShowsTimestamps: Bool { showTimestamps }

    var chatMessageFontSize: CGFloat {
        #if os(tvOS)
        return tvChatFontSize
        #else
        let scaled = (Self.baseFontSize + CGFloat(fontSizeDelta)) * CGFloat(messageScale)
        return max(10, scaled)
        #endif
    }

    /// Studio's chat on a TV is read from across the room: four sizes, in points on the 1080p canvas.
    var tvChatFontSize: CGFloat {
        switch tvChatTextSizePreference {
        case .small: 28
        case .medium: 34
        case .large: 40
        case .extraLarge: 48
        }
    }

    var chatPreferredEmoteScale: EmoteScale {
        #if os(tvOS)
        return .x2
        #else
        switch messageScale {
        case ..<0.85: return .x1
        case ..<1.5: return .x2
        case ..<2.25: return .x3
        default: return .x4
        }
        #endif
    }

    var chatLineSpacing: CGFloat {
        compactChat ? 0 : 2
    }

    var chatMessageFont: SupporterChatFont {
        SupporterLook.unlocked ? supporterChatFont : .standard
    }

    var chatShowsSupporterNameEffects: Bool {
        supporterNameEffectsEnabled
    }
}

/// What chat layout depends on: an open chat lays its messages out again only when one of these changes, including
/// the supporters' looks it draws.
struct ChatLayoutKey: Equatable, Sendable {
    let fontSize: CGFloat
    let showsTimestamps: Bool
    let lineSpacing: CGFloat
    let emoteScale: EmoteScale
    let font: SupporterChatFont
    let supporterNameEffects: Bool
    let supporters: Int
    let highlightMentions: Bool
    let highlightWords: [String]
    let highlightUsers: [String]
}

extension Settings {
    var chatLayoutKey: ChatLayoutKey {
        ChatLayoutKey(
            fontSize: chatMessageFontSize,
            showsTimestamps: chatShowsTimestamps,
            lineSpacing: chatLineSpacing,
            emoteScale: chatPreferredEmoteScale,
            font: chatMessageFont,
            supporterNameEffects: chatShowsSupporterNameEffects,
            supporters: SupporterDirectory.shared.revision,
            highlightMentions: highlightMentions,
            highlightWords: highlightWordList,
            highlightUsers: highlightUserList
        )
    }
}
