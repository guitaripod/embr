import Foundation
import Testing
@testable import EmbrCore

@Suite("LiveLatency")
struct LiveLatencyTests {
    private func quality(_ name: String, _ resolution: String?, _ bandwidth: Int?, audio: Bool = false) -> StreamQuality {
        StreamQuality(name: name, url: URL(string: "https://example.com/\(name).m3u8")!, bandwidth: bandwidth, resolution: resolution, isAudioOnly: audio)
    }

    private var twitch: [StreamQuality] {
        [
            quality("1080p60", "1920x1080", 8_042_999),
            quality("720p60", "1280x720", 3_322_199),
            quality("480p", "852x480", 1_327_200),
            quality("360p", "640x360", 627_900),
            quality("160p", "284x160", 216_299),
            quality("audio_only", nil, 160_000, audio: true),
        ]
    }

    @Test("Auto in Hyper plays the richest variant up to 720p")
    func autoCapsAt720() {
        #expect(LiveLatency.hyperQuality(from: twitch)?.name == "720p60")
    }

    @Test("A quality the viewer picked wins when the stream offers it")
    func preferredWins() {
        #expect(LiveLatency.hyperQuality(from: twitch, preferredName: "1080p60")?.name == "1080p60")
        #expect(LiveLatency.hyperQuality(from: twitch, preferredName: "1440p60")?.name == "720p60")
    }

    @Test("Audio only is never the pinned picture, even when asked for by name")
    func neverAudioOnly() {
        #expect(LiveLatency.hyperQuality(from: twitch, preferredName: "audio_only")?.name == "720p60")
    }

    @Test("A stream with nothing at or under 720p plays its smallest video")
    func smallestWhenAllTall() {
        let tall = [quality("1440p60", "2560x1440", 12_000_000), quality("1080p60", "1920x1080", 8_000_000)]
        #expect(LiveLatency.hyperQuality(from: tall)?.name == "1080p60")
    }

    @Test("No video, no pick")
    func noVideo() {
        #expect(LiveLatency.hyperQuality(from: [quality("audio_only", nil, 160_000, audio: true)]) == nil)
        #expect(LiveLatency.hyperQuality(from: []) == nil)
    }

    @Test("A variant without a resolution is never the Auto pick")
    func missingResolution() {
        let odd = [quality("chunked", nil, 9_000_000), quality("720p", "1280x720", 3_000_000)]
        #expect(LiveLatency.hyperQuality(from: odd)?.name == "720p")
    }
}

@Suite("PlaybackResolution latency")
struct PlaybackResolutionLatencyTests {
    private let standard = URL(string: "https://api.midgarcorp.cc/v1/embr/hls/proxy?src=a&exp=1&sig=s")!
    private let hyper = URL(string: "https://api.midgarcorp.cc/v1/embr/hls/proxy?src=a&exp=1&sig=h&latency=hyper")!

    @Test("A session with a Hyper link switches between the two and back")
    func switchesBothWays() {
        let resolution = PlaybackResolution(masterPlaylistURL: standard, expiresAt: Date(timeIntervalSince1970: 5), hyperPlaylistURL: hyper)
        #expect(resolution.latency == .standard)
        let fast = resolution.withLatency(.hyper)
        #expect(fast.masterPlaylistURL == hyper)
        #expect(fast.latency == .hyper)
        #expect(fast.expiresAt == Date(timeIntervalSince1970: 5))
        #expect(fast.withLatency(.standard).masterPlaylistURL == standard)
        #expect(fast.withLatency(.standard) == resolution)
    }

    @Test("A session without one stays standard when Hyper is asked for")
    func noHyperLink() {
        let resolution = PlaybackResolution(masterPlaylistURL: standard)
        #expect(!resolution.offersHyper)
        #expect(resolution.withLatency(.hyper).masterPlaylistURL == standard)
        #expect(resolution.withLatency(.hyper).latency == .standard)
    }

    @Test("Twitch's own master is the src the proxy link carries, and nothing for any other link")
    func upstreamMaster() {
        let usher = "https://usher.ttvnw.net/api/channel/hls/abc.m3u8?sig=x&token=%7B%22a%22%3A1%7D"
        var components = URLComponents(string: "https://api.midgarcorp.cc/v1/embr/hls/proxy")!
        components.queryItems = [URLQueryItem(name: "src", value: usher), URLQueryItem(name: "exp", value: "1"), URLQueryItem(name: "sig", value: "s")]
        let resolution = PlaybackResolution(masterPlaylistURL: components.url!, hyperPlaylistURL: hyper)
        #expect(resolution.upstreamMasterURL?.absoluteString == usher)
        #expect(resolution.withLatency(.hyper).upstreamMasterURL?.absoluteString == usher)
        #expect(PlaybackResolution(masterPlaylistURL: URL(string: "https://clips.example/a.mp4")!).upstreamMasterURL == nil)
    }
}
