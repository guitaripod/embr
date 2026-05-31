import UIKit
import EmbrCore

extension Settings: MessageLayoutSettings {
    private static let baseFontSize: CGFloat = 14

    var chatShowsTimestamps: Bool { showTimestamps }

    var chatMessageFontSize: CGFloat {
        let scaled = (Self.baseFontSize + CGFloat(fontSizeDelta)) * CGFloat(messageScale)
        return max(10, scaled)
    }

    var chatPreferredEmoteScale: EmoteScale {
        switch messageScale {
        case ..<0.85: return .x1
        case ..<1.5: return .x2
        case ..<2.25: return .x3
        default: return .x4
        }
    }

    var chatLineSpacing: CGFloat {
        compactChat ? 0 : 2
    }
}
