import UIKit
import EmbrCore

protocol ImageLoading: Sendable {
    func image(for url: URL, targetScale: CGFloat) async -> UIImage?
    func emoteImage(for emote: Emote, scale: EmoteScale) async -> UIImage?
    func badgeImage(for badge: Badge, scale: EmoteScale) async -> UIImage?
    func prefetch(_ urls: [URL])
    func cachedImage(for url: URL) -> UIImage?
}
