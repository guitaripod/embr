import Foundation
import EmbrCore
import MidgarCore

/// Where each clip's video lives. Resolving a clip asks Embr's worker for a signed MP4, which takes a few hundred
/// milliseconds, so the feed resolves the clips around the one on screen ahead of time and every request for the same
/// clip shares one lookup. A clip the worker can't resolve falls back to the MP4 next to its thumbnail.
actor ClipSourceCache {
    static let shared = ClipSourceCache()

    private let resolve: @Sendable (String) async throws -> URL
    private var resolved: [String: URL] = [:]
    private var inFlight: [String: Task<URL?, Never>] = [:]
    private let capacity = 120

    init(resolve: @escaping @Sendable (String) async throws -> URL = { slug in
        try await PlaybackResolver.shared.resolveClip(slug: slug)
    }) {
        self.resolve = resolve
    }

    /// The playable URL for `clip`, or nil when neither the worker nor the thumbnail fallback has one.
    func url(for clip: Clip) async -> URL? {
        if let known = resolved[clip.id] { return known }
        if let running = inFlight[clip.id] { return await running.value }
        let resolve = resolve
        let fallback = Self.mp4(besideThumbnail: clip.thumbnailURL)
        let task = Task<URL?, Never> {
            do {
                return try await resolve(clip.id)
            } catch {
                MidgarLog.notice("clip \(clip.id) unresolved, \(fallback == nil ? "no fallback" : "using the thumbnail MP4"): \(error)", category: .playback)
                return fallback
            }
        }
        inFlight[clip.id] = task
        let url = await task.value
        inFlight[clip.id] = nil
        if let url { remember(url, for: clip.id) }
        return url
    }

    /// Starts resolving `clips` without waiting, so they are ready by the time they scroll into view.
    func prefetch(_ clips: [Clip]) {
        for clip in clips where resolved[clip.id] == nil && inFlight[clip.id] == nil {
            Task { _ = await self.url(for: clip) }
        }
    }

    /// Forgets a resolved URL, for a retry after the signed link expired or failed to load.
    func forget(_ clipID: String) {
        resolved[clipID] = nil
    }

    private func remember(_ url: URL, for clipID: String) {
        if resolved.count >= capacity, let oldest = resolved.keys.first {
            resolved[oldest] = nil
        }
        resolved[clipID] = url
    }

    /// Twitch keeps a clip's MP4 at its thumbnail's address with the preview suffix swapped for `.mp4`.
    nonisolated static func mp4(besideThumbnail thumbnail: URL?) -> URL? {
        guard let raw = thumbnail?.absoluteString,
              let range = raw.range(of: "-preview-[0-9]+x[0-9]+\\.jpg", options: .regularExpression) else { return nil }
        return URL(string: raw.replacingCharacters(in: range, with: ".mp4"))
    }
}
