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
    private let standard = URL(string: "https://api.midgarcorp.cc/v1/embr/hls/proxy?src=https%3A%2F%2Fusher.ttvnw.net%2Fapi%2Fchannel%2Fhls%2Fa.m3u8%3Fsig%3Dx%26token%3D%257B%257D&exp=1794864299&sig=2a62")!

    @Test("Hyper adds the latency query and keeps the signed source untouched")
    func addsHyper() {
        let hyper = PlaybackResolution(masterPlaylistURL: standard).withLatency(.hyper)
        #expect(hyper.masterPlaylistURL.absoluteString == standard.absoluteString + "&latency=hyper")
    }

    @Test("Standard takes it away again, and switching twice changes nothing more")
    func roundTrips() {
        let hyper = PlaybackResolution(masterPlaylistURL: standard, expiresAt: Date(timeIntervalSince1970: 5)).withLatency(.hyper)
        let back = hyper.withLatency(.standard)
        #expect(back.masterPlaylistURL == standard)
        #expect(back.expiresAt == Date(timeIntervalSince1970: 5))
        #expect(hyper.withLatency(.hyper).masterPlaylistURL == hyper.masterPlaylistURL)
        #expect(PlaybackResolution(masterPlaylistURL: standard).withLatency(.standard).masterPlaylistURL == standard)
    }
}
