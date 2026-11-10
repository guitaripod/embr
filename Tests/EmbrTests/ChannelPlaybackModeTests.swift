import Foundation
import Testing

@testable import Embr

struct ChannelPlaybackModeTests {
    private static let livingRoom = ExternalRoute(deviceName: "Living Room")

    @Test func chatOnlyStopsAStreamPlayingOnThePhone() {
        let mode = ChannelPlaybackMode(chatOnly: true)
        #expect(!mode.streamPlays)
        #expect(!mode.showsVideo)
        #expect(!mode.showsMiniPlayer)
    }

    @Test func chatOnlyKeepsATVPlayingAndShowsTheMiniPlayer() {
        let mode = ChannelPlaybackMode(chatOnly: true, externalRoute: Self.livingRoom)
        #expect(mode.streamPlays)
        #expect(!mode.showsVideo)
        #expect(mode.showsMiniPlayer)
    }

    @Test func aTVWithTheVideoShowingNeedsNoMiniPlayer() {
        let mode = ChannelPlaybackMode(externalRoute: Self.livingRoom)
        #expect(mode.streamPlays)
        #expect(mode.showsVideo)
        #expect(!mode.showsMiniPlayer)
    }

    @Test func audioOnlyShowsTheMiniPlayerInPlaceOfTheVideo() {
        let mode = ChannelPlaybackMode(audioOnly: true)
        #expect(mode.streamPlays)
        #expect(!mode.showsVideo)
        #expect(mode.showsMiniPlayer)
    }

    @Test func theRouteNamesTheTVOrSaysAnotherScreen() {
        #expect(Self.livingRoom.playingOnText == "Playing on Living Room")
        #expect(ExternalRoute(deviceName: nil).playingOnText == "Playing on another screen")
        #expect(ExternalRoute(deviceName: "").playingOnText == "Playing on another screen")
    }
}
