import EmbrCore
import Foundation
import Testing

@testable import Embr

struct ClipFeedTests {
    private static func clip(_ id: String, thumbnail: String? = nil) -> Clip {
        Clip(
            id: id,
            broadcasterID: "1",
            broadcasterName: "Someone",
            creatorName: "clipper",
            title: "A clip",
            viewCount: 10,
            createdAt: Date(timeIntervalSince1970: 0),
            thumbnailURL: thumbnail.flatMap(URL.init(string:))
        )
    }

    @Test func concurrentRequestsForOneClipShareOneLookup() async {
        let calls = LockedBox(0)
        let cache = ClipSourceCache { slug in
            calls.value += 1
            try await Task.sleep(nanoseconds: 50_000_000)
            return URL(string: "https://example.com/\(slug).mp4")!
        }
        let clip = Self.clip("Bright")
        async let first = cache.url(for: clip)
        async let second = cache.url(for: clip)
        let urls = await [first, second]
        #expect(urls.allSatisfy { $0?.absoluteString == "https://example.com/Bright.mp4" })
        #expect(calls.value == 1)
        _ = await cache.url(for: clip)
        #expect(calls.value == 1)
    }

    @Test func anUnresolvedClipFallsBackToTheMP4BesideItsThumbnail() async {
        let cache = ClipSourceCache { _ in throw URLError(.badServerResponse) }
        let clip = Self.clip("Calm", thumbnail: "https://clips-media-assets2.twitch.tv/AT-cm%7C123-preview-480x272.jpg")
        let url = await cache.url(for: clip)
        #expect(url?.absoluteString == "https://clips-media-assets2.twitch.tv/AT-cm%7C123.mp4")
    }

    @Test func aClipWithNoSourceAtAllIsNil() async {
        let cache = ClipSourceCache { _ in throw URLError(.badServerResponse) }
        #expect(await cache.url(for: Self.clip("Gone")) == nil)
    }

    @Test func forgettingAClipResolvesItAgain() async {
        let calls = LockedBox(0)
        let cache = ClipSourceCache { slug in
            calls.value += 1
            return URL(string: "https://example.com/\(slug)-\(calls.value).mp4")!
        }
        let clip = Self.clip("Swift")
        _ = await cache.url(for: clip)
        await cache.forget(clip.id)
        let again = await cache.url(for: clip)
        #expect(again?.absoluteString == "https://example.com/Swift-2.mp4")
    }

    @Test func reportedClipsLeaveEveryList() throws {
        let defaults = try #require(UserDefaults(suiteName: "ClipFeedTests.hidden.\(UUID().uuidString)"))
        let hidden = HiddenClips(defaults: defaults)
        hidden.hide("b")
        hidden.hide("b")
        let visible = hidden.visible([Self.clip("a"), Self.clip("b"), Self.clip("c")])
        #expect(visible.map(\.id) == ["a", "c"])
        #expect(hidden.ids == ["b"])
    }
}
