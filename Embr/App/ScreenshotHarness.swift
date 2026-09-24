#if DEBUG
import UIKit

/// DEBUG-only capture state for App Store / marketing screenshots. Set from launch
/// arguments in `SceneDelegate.handleScreenshotRoute` and read by the posed screens.
/// Never compiled into a Release build.
@MainActor
enum ScreenshotHarness {
    enum ChannelPose: String {
        case normal
        case audio
        case chat
    }

    static var channelPose: ChannelPose = .normal
    static var searchQuery: String?
    static var seededFollow = false
    static var previewTips = false

    /// Popular channels shown, live, in the posed Following tab. Real channels resolved
    /// live via the public API; only the "you follow these" relationship is seeded.
    static let curatedFollowLogins = [
        "caedrel", "kaicenat", "hasanabi", "tarik", "loltyler1",
        "summit1g", "sodapoppin", "jynxzi", "zackrawrr", "pokimane",
    ]
}
#endif
