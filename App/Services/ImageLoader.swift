import UIKit
import EmbrCore
import SDWebImage
import SDWebImageWebPCoder
import MidgarCore

final class ImageLoader: ImageLoading {
    static let shared = ImageLoader()

    /// SDWebImage documents its manager and prefetcher as safe to call from any queue; they are never reassigned.
    nonisolated(unsafe) private let manager: SDWebImageManager
    /// See `manager`.
    nonisolated(unsafe) private let prefetcher: SDWebImagePrefetcher

    init(manager: SDWebImageManager = .shared, prefetcher: SDWebImagePrefetcher = .shared) {
        self.manager = manager
        self.prefetcher = prefetcher
        SDImageCodersManager.shared.addCoder(SDImageWebPCoder.shared)
        Self.limitCaches(SDImageCache.shared.config)
    }

    /// Bounds the image caches: decoded images in memory to what a few screens of thumbnails and a busy chat's emotes
    /// need (the system still purges them under memory pressure), and files on disk to a size that does not keep
    /// growing with every channel visited.
    private static func limitCaches(_ config: SDImageCacheConfig) {
        config.maxMemoryCost = 120 * 1024 * 1024
        config.maxDiskSize = 300 * 1024 * 1024
        config.maxDiskAge = 60 * 60 * 24 * 7
    }

    func avatarImage(for url: URL, side: CGFloat, scale: CGFloat) async -> UIImage? {
        await load(url: url, context: Self.avatarContext(side: side, scale: scale))
    }

    func cachedAvatar(for url: URL, side: CGFloat, scale: CGFloat) -> UIImage? {
        guard let key = manager.cacheKey(for: url, context: Self.avatarContext(side: side, scale: scale)) else { return nil }
        return SDImageCache.shared.imageFromMemoryCache(forKey: key)
    }

    private static func avatarContext(side: CGFloat, scale: CGFloat) -> [SDWebImageContextOption: Any] {
        let pixels = ceil(side * scale)
        return [
            .imageThumbnailPixelSize: CGSize(width: pixels, height: pixels),
            .imagePreserveAspectRatio: true,
            .imageScaleFactor: scale,
        ]
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
        #if DEBUG
        if DemoWorld.isActive, !url.isFileURL { return DemoArt.image(for: url) }
        #endif
        let request = ImageRequest()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                request.begin(continuation)
                let operation = manager.loadImage(
                    with: url,
                    options: [.retryFailed, .scaleDownLargeImages],
                    context: context,
                    progress: nil
                ) { image, _, error, _, _, _ in
                    if let error, (error as NSError).code != SDWebImageError.cancelled.rawValue {
                        MidgarLog.debug("Image load failed for \(url): \(error)", category: .ui)
                    }
                    request.finish(image)
                }
                request.attach(operation)
            }
        } onCancel: {
            request.cancel()
        }
    }
}

/// One image load that a cell scrolling away can call off: cancelling stops the download (unless another view waits
/// for the same image) and returns nil at once, and the continuation is resumed exactly once whichever comes first.
private final class ImageRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var operation: SDWebImageCombinedOperation?
    private var cancelled = false

    func begin(_ continuation: CheckedContinuation<UIImage?, Never>) {
        lock.lock()
        let alreadyCancelled = cancelled
        if !alreadyCancelled { self.continuation = continuation }
        lock.unlock()
        if alreadyCancelled { continuation.resume(returning: nil) }
    }

    func attach(_ operation: SDWebImageCombinedOperation?) {
        lock.lock()
        let cancelNow = cancelled
        if !cancelNow { self.operation = operation }
        lock.unlock()
        if cancelNow { operation?.cancel() }
    }

    func finish(_ image: UIImage?) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        operation = nil
        lock.unlock()
        waiting?.resume(returning: image)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let waiting = continuation
        let running = operation
        continuation = nil
        operation = nil
        lock.unlock()
        running?.cancel()
        waiting?.resume(returning: nil)
    }
}
