import Foundation
import Testing
@testable import EmbrCore

@Suite struct HLSPlaylistParserTests {
    let master = """
    #EXTM3U
    #EXT-X-TWITCH-INFO:NODE="video-edge-1.ams"
    #EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="chunked",NAME="1080p60",AUTOSELECT=YES,DEFAULT=YES
    #EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,FRAME-RATE=60.000,VIDEO="chunked"
    https://video-edge.example/chunked.m3u8
    #EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="720p60",NAME="720p60",AUTOSELECT=YES,DEFAULT=NO
    #EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720,FRAME-RATE=60.000,VIDEO="720p60"
    https://video-edge.example/720p60.m3u8
    #EXT-X-MEDIA:TYPE=VIDEO,GROUP-ID="audio_only",NAME="audio_only",AUTOSELECT=NO,DEFAULT=NO
    #EXT-X-STREAM-INF:BANDWIDTH=160000,CODECS="mp4a.40.2",VIDEO="audio_only"
    https://video-edge.example/audio_only.m3u8
    """

    @Test func parsesThreeVariants() {
        let variants = HLSPlaylistParser.masterVariants(master)
        #expect(variants.count == 3)
        #expect(variants[0].bandwidth == 6000000)
        #expect(variants[0].resolution == "1920x1080")
        #expect(variants[0].frameRate == 60.0)
        #expect(variants[0].groupID == "chunked")
        #expect(variants[0].videoName == "1080p60")
        #expect(variants[0].url == "https://video-edge.example/chunked.m3u8")
        #expect(variants[2].groupID == "audio_only")
    }

    @Test func mapsQualitiesWithNames() {
        let qualities = HLSPlaylistParser.qualities(master)
        #expect(qualities.count == 3)
        #expect(qualities.map(\.name) == ["1080p60", "720p60", "audio_only"])
        #expect(qualities[0].isAudioOnly == false)
        #expect(qualities[2].isAudioOnly == true)
        #expect(qualities[0].url == URL(string: "https://video-edge.example/chunked.m3u8"))
        #expect(qualities[1].bandwidth == 3000000)
    }

    @Test func derivesNameFromResolutionWhenNoMediaName() {
        let playlist = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720,FRAME-RATE=30.000,VIDEO="720p30"
        https://video-edge.example/720p30.m3u8
        """
        let qualities = HLSPlaylistParser.qualities(playlist)
        #expect(qualities.count == 1)
        #expect(qualities[0].name == "720p30")
    }

    @Test func parsesSegmentsAndFlagsPrefetch() {
        let media = """
        #EXTM3U
        #EXT-X-VERSION:6
        #EXT-X-TARGETDURATION:2
        #EXT-X-MEDIA-SEQUENCE:100
        #EXTINF:2.000,live
        https://video-edge.example/100.ts
        #EXTINF:2.000,live
        https://video-edge.example/101.ts
        #EXT-X-TWITCH-PREFETCH:https://video-edge.example/102-prefetch.ts
        #EXT-X-TWITCH-PREFETCH:https://video-edge.example/103-prefetch.ts
        """
        let segments = HLSPlaylistParser.segments(media)
        #expect(segments.count == 4)
        #expect(segments[0].uri == "https://video-edge.example/100.ts")
        #expect(segments[0].duration == 2.0)
        #expect(segments[0].isPrefetch == false)
        #expect(segments[2].isPrefetch == true)
        #expect(segments[2].uri == "https://video-edge.example/102-prefetch.ts")
        #expect(segments[3].isPrefetch == true)
        let prefetchCount = segments.filter(\.isPrefetch).count
        #expect(prefetchCount == 2)
    }

    @Test func attachesDateRangeAndDiscontinuityTags() {
        let media = """
        #EXTM3U
        #EXT-X-DATERANGE:ID="stitched-ad-1",CLASS="twitch-stitched-ad",START-DATE="2024-01-01T00:00:00Z",DURATION=30.0
        #EXT-X-DISCONTINUITY
        #EXTINF:2.000,Amazon
        https://ad.example/ad.ts
        """
        let segments = HLSPlaylistParser.segments(media)
        #expect(segments.count == 1)
        #expect(segments[0].attachedTags.contains(where: { $0.hasPrefix("#EXT-X-DATERANGE:") }))
        #expect(segments[0].attachedTags.contains("#EXT-X-DISCONTINUITY"))
    }
}

@Suite struct HLSAdStripperTests {
    @Test func stripsStitchedAdDateRangeAndSegmentsPreservingPrefetch() {
        let media = """
        #EXTM3U
        #EXT-X-VERSION:6
        #EXT-X-TARGETDURATION:2
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:2.000,live
        https://video-edge.example/0.ts
        #EXT-X-DATERANGE:ID="stitched-ad-roll-1",CLASS="twitch-stitched-ad",START-DATE="2024-01-01T00:00:00Z",DURATION=4.0
        #EXT-X-DISCONTINUITY
        #EXTINF:2.000,Amazon
        https://ad.example/ad-0.ts
        #EXTINF:2.000,Amazon
        https://ad.example/ad-1.ts
        #EXT-X-DISCONTINUITY
        #EXTINF:2.000,live
        https://video-edge.example/1.ts
        #EXT-X-TWITCH-PREFETCH:https://video-edge.example/2-prefetch.ts
        """
        let stripped = HLSAdStripper.strip(media)

        #expect(stripped.contains("#EXTM3U"))
        #expect(stripped.contains("#EXT-X-TARGETDURATION:2"))
        #expect(stripped.contains("https://video-edge.example/0.ts"))
        #expect(stripped.contains("https://video-edge.example/1.ts"))
        #expect(stripped.contains("#EXT-X-TWITCH-PREFETCH:https://video-edge.example/2-prefetch.ts"))

        #expect(!stripped.contains("twitch-stitched-ad"))
        #expect(!stripped.contains("https://ad.example/ad-0.ts"))
        #expect(!stripped.contains("https://ad.example/ad-1.ts"))
        #expect(!stripped.contains(",Amazon"))
    }

    @Test func stripsByIDPrefixWhenClassMissing() {
        let media = """
        #EXTM3U
        #EXTINF:2.000,live
        https://video-edge.example/0.ts
        #EXT-X-DATERANGE:ID="stitched-ad-xyz",START-DATE="2024-01-01T00:00:00Z"
        #EXTINF:2.000,Amazon
        https://ad.example/ad.ts
        #EXTINF:2.000,live
        https://video-edge.example/1.ts
        """
        let stripped = HLSAdStripper.strip(media)
        #expect(!stripped.contains("stitched-ad-xyz"))
        #expect(!stripped.contains("https://ad.example/ad.ts"))
        #expect(stripped.contains("https://video-edge.example/0.ts"))
        #expect(stripped.contains("https://video-edge.example/1.ts"))
    }

    @Test func keepsNormalSegmentsUntouched() {
        let media = """
        #EXTM3U
        #EXT-X-VERSION:6
        #EXTINF:2.000,live
        https://video-edge.example/0.ts
        #EXTINF:2.000,live
        https://video-edge.example/1.ts
        """
        let stripped = HLSAdStripper.strip(media)
        #expect(stripped.contains("https://video-edge.example/0.ts"))
        #expect(stripped.contains("https://video-edge.example/1.ts"))
        #expect(stripped.contains("#EXTINF:2.000,live"))
    }
}

@Suite struct GQLPlaybackTests {
    @Test func liveRequestBodyContainsPersistedHashAndVariables() throws {
        let data = GQLPlayback.liveRequestBody(login: "shroud")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["operationName"] as? String == "PlaybackAccessToken")

        let variables = json?["variables"] as? [String: Any]
        #expect(variables?["isLive"] as? Bool == true)
        #expect(variables?["isVod"] as? Bool == false)
        #expect(variables?["login"] as? String == "shroud")
        #expect(variables?["playerType"] as? String == "site")

        let extensions = json?["extensions"] as? [String: Any]
        let persisted = extensions?["persistedQuery"] as? [String: Any]
        #expect(persisted?["version"] as? Int == 1)
        #expect(persisted?["sha256Hash"] as? String == "ed230aa1e33e07eebb8928504583da78a5173989fadfb1ac94be06a04f3cdbe9")
    }

    @Test func vodRequestBodyHasVodFlags() throws {
        let data = GQLPlayback.vodRequestBody(vodID: "123456789")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let variables = json?["variables"] as? [String: Any]
        #expect(variables?["isLive"] as? Bool == false)
        #expect(variables?["isVod"] as? Bool == true)
        #expect(variables?["vodID"] as? String == "123456789")
    }

    @Test func decodesLiveAccessToken() throws {
        let raw = """
        {"data":{"streamPlaybackAccessToken":{"value":"{\\"channel\\":\\"shroud\\"}","signature":"abc123","__typename":"PlaybackAccessToken"}}}
        """
        let token = try GQLPlayback.liveAccessToken(from: Data(raw.utf8))
        #expect(token.signature == "abc123")
        #expect(token.value.contains("shroud"))
    }

    @Test func decodesVODAccessToken() throws {
        let raw = """
        {"data":{"videoPlaybackAccessToken":{"value":"vodtoken","signature":"sig999"}}}
        """
        let token = try GQLPlayback.vodAccessToken(from: Data(raw.utf8))
        #expect(token.value == "vodtoken")
        #expect(token.signature == "sig999")
    }

    @Test func usherURLHasHostAndQueryKeys() throws {
        let url = GQLPlayback.usherURL(
            login: "shroud",
            token: "tok",
            signature: "sig",
            clientID: GQLPlayback.webClientID
        )
        #expect(url.host == "usher.ttvnw.net")
        #expect(url.path == "/api/channel/hls/shroud.m3u8")

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(items["client_id"] == GQLPlayback.webClientID)
        #expect(items["token"] == "tok")
        #expect(items["sig"] == "sig")
        #expect(items["allow_source"] == "true")
        #expect(items["allow_audio_only"] == "true")
        #expect(items["playlist_include_framerate"] == "true")
        #expect(items["player"] == "twitchweb")
    }

    @Test func usherVODURLHasVodPath() {
        let url = GQLPlayback.usherVODURL(id: "42", token: "t", signature: "s", clientID: GQLPlayback.webClientID)
        #expect(url.host == "usher.ttvnw.net")
        #expect(url.path == "/vod/42.m3u8")
    }

    @Test func webClientIDIsPublicWebValue() {
        #expect(GQLPlayback.webClientID == "kimne78kx3ncx6brgo4mv6wki5h1ko")
    }
}
