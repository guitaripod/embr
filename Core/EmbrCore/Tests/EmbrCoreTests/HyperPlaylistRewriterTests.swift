import Foundation
import Testing
@testable import EmbrCore

@Suite("HyperPlaylistRewriter")
struct HyperPlaylistRewriterTests {
    private let base = URL(string: "https://video-weaver.eun13.hls.ttvnw.net/v1/playlist/abc.m3u8")!

    private var live: String {
        [
            "#EXTM3U",
            "#EXT-X-VERSION:6",
            "#EXT-X-TARGETDURATION:5",
            "#EXT-X-MEDIA-SEQUENCE:120",
            "#EXT-X-START:TIME-OFFSET=0.000",
            "#EXT-X-MAP:URI=\"init.mp4\"",
            "#EXT-X-PROGRAM-DATE-TIME:2026-11-15T20:30:40.042Z",
            "#EXTINF:2.000,live",
            "https://edge.hls.ttvnw.net/v1/segment/a.mp4",
            "#EXT-X-PROGRAM-DATE-TIME:2026-11-15T20:30:42.042Z",
            "#EXTINF:2.000,live",
            "https://edge.hls.ttvnw.net/v1/segment/b.mp4",
            "#EXT-X-TWITCH-PREFETCH:https://edge.hls.ttvnw.net/v1/segment/p1.mp4",
            "#EXT-X-TWITCH-PREFETCH:https://edge.hls.ttvnw.net/v1/segment/p2.mp4",
        ].joined(separator: "\n")
    }

    private func lines(_ text: String) -> [String] { text.components(separatedBy: "\n") }
    private func uris(_ text: String) -> [String] { lines(text).filter { $0.hasPrefix("https://") } }

    @Test("Prefetch lines become segments with program dates, and the target duration is Twitch's real one")
    func prefetchBecomesSegments() {
        var rewriter = HyperPlaylistRewriter()
        let out = lines(rewriter.rewrite(live, playlistURL: base))
        #expect(!out.contains { $0.hasPrefix("#EXT-X-TWITCH-PREFETCH") || $0.hasPrefix("#EXT-X-START") })
        #expect(out.filter { $0.hasPrefix("#EXTINF") }.count == 4)
        #expect(out.contains("#EXT-X-PROGRAM-DATE-TIME:2026-11-15T20:30:44.042Z"))
        #expect(out.contains("#EXT-X-PROGRAM-DATE-TIME:2026-11-15T20:30:46.042Z"))
        #expect(out.contains("#EXT-X-TARGETDURATION:2"))
        #expect(out.contains("#EXT-X-MAP:URI=\"https://video-weaver.eun13.hls.ttvnw.net/v1/playlist/init.mp4\""))
    }

    @Test("A sequence number keeps the URI first seen for it when Twitch renames its finished prefetch")
    func stableAcrossReloads() {
        var rewriter = HyperPlaylistRewriter()
        let first = uris(rewriter.rewrite(live, playlistURL: base))
        let reloaded = live
            .replacingOccurrences(of: "#EXT-X-MEDIA-SEQUENCE:120", with: "#EXT-X-MEDIA-SEQUENCE:121")
            .replacingOccurrences(of: "#EXT-X-PROGRAM-DATE-TIME:2026-11-15T20:30:40.042Z\n#EXTINF:2.000,live\nhttps://edge.hls.ttvnw.net/v1/segment/a.mp4\n", with: "")
            .replacingOccurrences(of: "#EXT-X-TWITCH-PREFETCH:https://edge.hls.ttvnw.net/v1/segment/p1.mp4", with: "#EXTINF:2.000,live\nhttps://edge.hls.ttvnw.net/v1/segment/final-122.mp4")
            .replacingOccurrences(of: "#EXT-X-TWITCH-PREFETCH:https://edge.hls.ttvnw.net/v1/segment/p2.mp4", with: "#EXT-X-TWITCH-PREFETCH:https://edge.hls.ttvnw.net/v1/segment/p2.mp4\n#EXT-X-TWITCH-PREFETCH:https://edge.hls.ttvnw.net/v1/segment/p3.mp4")
        let second = uris(rewriter.rewrite(reloaded, playlistURL: base))
        #expect(first == ["a", "b", "p1", "p2"].map { "https://edge.hls.ttvnw.net/v1/segment/\($0).mp4" })
        #expect(second == ["b", "p1", "p2", "p3"].map { "https://edge.hls.ttvnw.net/v1/segment/\($0).mp4" })
    }

    @Test("A prefetch inside an ad is stripped with the ad")
    func prefetchInAd() {
        let inAd = [
            "#EXTM3U", "#EXT-X-TARGETDURATION:5", "#EXT-X-MEDIA-SEQUENCE:10",
            "#EXTINF:2.000,live", "https://edge.hls.ttvnw.net/c.mp4",
            "#EXT-X-DATERANGE:ID=\"stitched-ad-1\",CLASS=\"twitch-stitched-ad\",START-DATE=\"2026-11-15T20:30:42.042Z\"",
            "#EXTINF:2.000,Amazon|123", "https://edge.hls.ttvnw.net/ad.mp4",
            "#EXT-X-TWITCH-PREFETCH:https://edge.hls.ttvnw.net/ad-next.mp4",
        ].joined(separator: "\n")
        var rewriter = HyperPlaylistRewriter()
        let out = rewriter.rewrite(inAd, playlistURL: base)
        #expect(!out.contains("Amazon"))
        #expect(uris(out) == ["https://edge.hls.ttvnw.net/c.mp4"])
    }

    @Test("When a preroll ends the content keeps Twitch's numbering and its own init segment")
    func prerollEnds() {
        let playlist = [
            "#EXTM3U", "#EXT-X-VERSION:6", "#EXT-X-TARGETDURATION:5", "#EXT-X-MEDIA-SEQUENCE:0",
            "#EXT-X-DATERANGE:ID=\"playlist-session-1\",CLASS=\"twitch-session\",START-DATE=\"2026-11-15T21:20:03.494Z\"",
            "#EXT-X-DATERANGE:ID=\"stitched-ad-1\",CLASS=\"twitch-stitched-ad\",START-DATE=\"2026-11-15T21:19:57.807Z\",DURATION=4.235",
            "#EXT-X-DISCONTINUITY", "#EXT-X-MAP:URI=\"https://cdn.ttvnw.net/ad-init.mp4\"",
            "#EXTINF:2.000,Amazon|1", "https://cdn.ttvnw.net/ad0.mp4",
            "#EXTINF:2.000,Amazon|1", "https://cdn.ttvnw.net/ad1.mp4",
            "#EXT-X-DISCONTINUITY", "#EXT-X-MAP:URI=\"https://cdn.ttvnw.net/live-init.mp4\"",
            "#EXT-X-PROGRAM-DATE-TIME:2026-11-15T21:20:01.807Z",
            "#EXTINF:2.000,live", "https://cdn.ttvnw.net/live2.mp4",
            "#EXT-X-TWITCH-PREFETCH:https://cdn.ttvnw.net/live3.mp4",
        ].joined(separator: "\n")
        var rewriter = HyperPlaylistRewriter()
        let out = lines(rewriter.rewrite(playlist, playlistURL: base))
        #expect(out.contains("#EXT-X-MEDIA-SEQUENCE:2"))
        #expect(out.contains("#EXT-X-MAP:URI=\"https://cdn.ttvnw.net/live-init.mp4\""))
        #expect(!out.contains("#EXT-X-MAP:URI=\"https://cdn.ttvnw.net/ad-init.mp4\""))
        #expect(!out.contains("#EXT-X-DISCONTINUITY"))
        #expect(out.contains { $0.contains("twitch-session") })
        #expect(!out.contains { $0.contains("stitched-ad") })
        #expect(uris(out.joined(separator: "\n")) == ["https://cdn.ttvnw.net/live2.mp4", "https://cdn.ttvnw.net/live3.mp4"])
    }

    @Test("A playlist of nothing but ads plays as it is, numbered from the start")
    func allAds() {
        let ads = ["#EXTM3U", "#EXT-X-TARGETDURATION:5", "#EXT-X-MEDIA-SEQUENCE:0", "#EXTINF:2.000,Amazon|1", "https://cdn.ttvnw.net/ad0.mp4"].joined(separator: "\n")
        var rewriter = HyperPlaylistRewriter()
        let out = lines(rewriter.rewrite(ads, playlistURL: base))
        #expect(out.contains("#EXT-X-MEDIA-SEQUENCE:0"))
        #expect(uris(out.joined(separator: "\n")) == ["https://cdn.ttvnw.net/ad0.mp4"])
    }

    @Test("Relative URIs come out absolute against the playlist")
    func relativeURIs() {
        let playlist = ["#EXTM3U", "#EXT-X-TARGETDURATION:2", "#EXT-X-MEDIA-SEQUENCE:4", "#EXTINF:2.000,live", "seg4.ts", "#EXT-X-TWITCH-PREFETCH:seg5.ts"].joined(separator: "\n")
        var rewriter = HyperPlaylistRewriter()
        #expect(uris(rewriter.rewrite(playlist, playlistURL: base)) == [
            "https://video-weaver.eun13.hls.ttvnw.net/v1/playlist/seg4.ts",
            "https://video-weaver.eun13.hls.ttvnw.net/v1/playlist/seg5.ts",
        ])
    }

    @Test("Never states a target duration below 2 or above what Twitch declared")
    func targetBounds() {
        var rewriter = HyperPlaylistRewriter()
        let short = live.replacingOccurrences(of: "#EXTINF:2.000,live", with: "#EXTINF:0.400,live")
        #expect(lines(rewriter.rewrite(short, playlistURL: base)).contains("#EXT-X-TARGETDURATION:2"))
        var other = HyperPlaylistRewriter()
        let long = live.replacingOccurrences(of: "#EXTINF:2.000,live\nhttps://edge.hls.ttvnw.net/v1/segment/b.mp4", with: "#EXTINF:9.000,live\nhttps://edge.hls.ttvnw.net/v1/segment/b.mp4")
        #expect(lines(other.rewrite(long, playlistURL: base)).contains("#EXT-X-TARGETDURATION:5"))
    }

    @Test("A finished VOD only gets absolute URIs")
    func vodUntouched() {
        let vod = ["#EXTM3U", "#EXT-X-PLAYLIST-TYPE:VOD", "#EXT-X-TARGETDURATION:10", "#EXTINF:10.000,", "0.ts", "#EXT-X-ENDLIST"].joined(separator: "\n")
        var rewriter = HyperPlaylistRewriter()
        let out = lines(rewriter.rewrite(vod, playlistURL: base))
        #expect(out.contains("#EXT-X-TARGETDURATION:10"))
        #expect(out.contains("https://video-weaver.eun13.hls.ttvnw.net/v1/playlist/0.ts"))
    }
}
