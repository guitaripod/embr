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

    /// Chat on a TV is read from the couch: the three sizes of the Apple TV's chat menu, in points on the 1080p canvas.
    var tvChatFontSize: CGFloat {
        switch tvChatTextSizePreference {
        case .small: 22
        case .medium: 26
        case .large: 31
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
}
