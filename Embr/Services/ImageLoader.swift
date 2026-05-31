import UIKit
import EmbrCore
import SDWebImage
import SDWebImageWebPCoder

final class ImageLoader: ImageLoading {
    static let shared = ImageLoader()

    nonisolated(unsafe) private let manager: SDWebImageManager
    nonisolated(unsafe) private let prefetcher: SDWebImagePrefetcher

    init(manager: SDWebImageManager = .shared, prefetcher: SDWebImagePrefetcher = .shared) {
        self.manager = manager
        self.prefetcher = prefetcher
        SDImageCodersManager.shared.addCoder(SDImageWebPCoder.shared)
    }

    func image(for url: URL, targetScale: CGFloat) async -> UIImage? {
        await load(url: url, context: [.imageScaleFactor: targetScale])
    }

    func emoteImage(for emote: Emote, scale: EmoteScale) async -> UIImage? {
        guard let url = emote.images.url(preferring: scale) else { return nil }
        let context: [SDWebImageContextOption: Any] = emote.isAnimated
            ? [.animatedImageClass: SDAnimatedImage.self]
            : [:]
        return await load(url: url, context: context)
    }

    func badgeImage(for badge: Badge, scale: EmoteScale) async -> UIImage? {
        guard let url = badge.images.url(preferring: scale) else { return nil }
        return await load(url: url, context: [:])
    }

    func prefetch(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        prefetcher.prefetchURLs(urls)
    }

    func cachedImage(for url: URL) -> UIImage? {
        guard let key = manager.cacheKey(for: url) else { return nil }
        return SDImageCache.shared.imageFromMemoryCache(forKey: key)
    }

    private func load(url: URL, context: [SDWebImageContextOption: Any]) async -> UIImage? {
        await withCheckedContinuation { continuation in
            manager.loadImage(
                with: url,
                options: [.retryFailed, .scaleDownLargeImages],
                context: context,
                progress: nil
            ) { image, _, error, _, _, _ in
                if let error {
                    AppLogger.shared.debug("Image load failed for \(url): \(error)", category: .ui)
                }
                continuation.resume(returning: image)
            }
        }
    }
}
