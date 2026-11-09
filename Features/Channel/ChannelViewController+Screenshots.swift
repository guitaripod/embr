#if DEBUG
import UIKit
import EmbrCore

extension ChannelViewController {
    func applyScreenshotPose() {
        if let keyboard = ScreenshotRouter.option("Keyboard") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                self?.chatController?.raiseKeyboardForScreenshot(emotes: keyboard == "emotes")
            }
            let draft = ScreenshotRouter.option("Draft")
            let replies = ScreenshotRouter.option("Reply") == "1"
            if draft != nil || replies {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
                    self?.chatController?.composeForScreenshot(draft: draft, reply: replies)
                }
            }
        }
        let pose = ScreenshotHarness.channelPose
        guard pose != .normal else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            switch pose {
            case .audio: self.videoController?.setAudioOnly(true)
            case .chat: self.setChatOnly(true)
            case .fullscreen: self.videoController?.toggleFullscreen()
            case .fullscreenChat:
                self.videoController?.toggleFullscreen()
                if !self.isFullscreenChatVisible { self.toggleFullscreenChat() }
            case .normal: break
            }
        }
    }

    /// A DEBUG capture can pose a signed-in viewer (`-screenshotChatAs <login>`) so the composer and keyboard show.
    static var posedChatUser: AuthenticatedUser? {
        ScreenshotRouter.option("ChatAs").map { AuthenticatedUser(id: "posed-\($0)", login: $0, displayName: $0, scopes: []) }
    }
}
#endif
