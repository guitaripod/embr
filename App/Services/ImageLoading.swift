import UIKit
import EmbrCore

protocol ImageLoading: Sendable {
    func image(for url: URL, targetScale: CGFloat) async -> UIImage?
    func emoteImage(for emote: Emote, scale: EmoteScale) async -> UIImage?
    func badgeImage(for badge: Badge, scale: EmoteScale) async -> UIImage?
    func prefetch(_ urls: [URL])
    func cachedImage(for url: URL) -> UIImage?
    /// A profile picture decoded at the size it is drawn rather than Twitch's 300-pixel original.
    func avatarImage(for url: URL, side: CGFloat, scale: CGFloat) async -> UIImage?
    func cachedAvatar(for url: URL, side: CGFloat, scale: CGFloat) -> UIImage?
}

extension ImageLoading {
    func avatarImage(for url: URL, side: CGFloat, scale: CGFloat) async -> UIImage? {
        await image(for: url, targetScale: scale)
    }

    func cachedAvatar(for url: URL, side: CGFloat, scale: CGFloat) -> UIImage? {
        cachedImage(for: url)
    }
}
