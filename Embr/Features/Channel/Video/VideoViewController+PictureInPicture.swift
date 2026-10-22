import AVKit
import UIKit
import MidgarCore

extension VideoViewController: @MainActor AVPictureInPictureControllerDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        MidgarLog.error("PiP failed: \(error.localizedDescription)", category: .playback)
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = true
        overlay.setPictureInPictureActive(true)
        overlay.hideControls()
        setImmersiveState(false)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = false
        overlay.setPictureInPictureActive(false)
        setImmersiveState(hostImmersiveState?() ?? restoredStandaloneImmersiveState)
        if pendingAudioOnlyOnPiPStop {
            pendingAudioOnlyOnPiPStop = false
            if isAudioOnly { enterAudioOnlyPlayback() }
        }
        if view.window == nil { teardownPlayerIfNeeded() }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        let host = parent ?? self
        if let presented = host.presentedViewController {
            presented.dismiss(animated: false)
        }
        if let nav = host.navigationController,
           nav.topViewController !== host,
           nav.viewControllers.contains(host) {
            nav.popToViewController(host, animated: false)
        }
        completionHandler(true)
    }
}
