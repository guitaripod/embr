#if DEBUG
import UIKit
import EmbrCore

/// DEBUG-only capture state for App Store / marketing screenshots. Set from launch
/// arguments in `SceneDelegate.handleScreenshotRoute` and read by the posed screens.
/// Never compiled into a Release build.
@MainActor
enum ScreenshotHarness {
    enum ChannelPose: String {
        case normal
        case audio
        case chat
        case fullscreen
        case fullscreenChat
    }

    static var isPosing = false
    static var skippedLogins: Set<String> = []
    static var channelPose: ChannelPose = .normal
    static var searchQuery: String?
    static var seededFollow = false
    static var previewTips = false
    /// Store panels on iPad are shot without the status bar, which iPadOS draws over the
    /// navigation bar of a window turned by the capture copy.
    static var hidesStatusBar = false

    /// Popular channels shown, live, in the posed Following tab. Real channels resolved
    /// live via the public API; only the "you follow these" relationship is seeded.
    /// Whether a live stream may appear in a store screenshot: nothing flagged mature, no
    /// gambling, which Twitch's front page carries at any hour, and none of the channels the
    /// capture named with `-screenshotSkip` (a stream whose picture is black, say).
    static func suitsStoreShot(_ stream: LiveStream) -> Bool {
        !stream.isMature && !gamblingCategories.contains(stream.gameName)
            && !stream.title.contains("18+") && !stream.title.contains("+18")
            && !skippedLogins.contains(stream.userLogin.lowercased())
    }

    /// The categories grid keeps gambling off the store too.
    static func suitsStoreShot(_ category: GameCategory) -> Bool {
        !gamblingCategories.contains(category.name)
    }

    private static let gamblingCategories = ["Slots", "Virtual Casino", "Poker", "Casino"]

    static let curatedFollowLogins = [
        "caedrel", "kaicenat", "hasanabi", "tarik", "loltyler1",
        "summit1g", "sodapoppin", "jynxzi", "zackrawrr", "pokimane",
    ]
}
#endif
