import AVKit
import UIKit
import EmbrCore
import MidgarCore

extension VideoViewController: VideoOverlayViewDelegate {
    func videoOverlayDidTapBack(_ overlay: VideoOverlayView) {
        dismissSelf()
    }

    func videoOverlayDidTapPlayPause(_ overlay: VideoOverlayView) {
        switch currentState {
        case .playing, .buffering, .loading:
            player.pause()
        case .ended where isSeekableSource:
            player.seek(to: 0)
            player.play()
        default:
            if case .live = source { player.seekToLive() }
            player.play()
        }
    }

    func videoOverlayDidTapQuality(_ overlay: VideoOverlayView, from sourceView: UIView) {
        presentQualityPicker(from: sourceView)
    }

    func videoOverlayDidTapPictureInPicture(_ overlay: VideoOverlayView) {
        triggerPictureInPicture()
    }

    func videoOverlayDidTapRetry(_ overlay: VideoOverlayView) {
        guard !didTeardownPlayer else { return }
        showingError = false
        recoveryAttempts = 0
        resolveAndLoad()
    }

    func videoOverlayDidTapMute(_ overlay: VideoOverlayView) {
        isMuted.toggle()
        player.setMuted(isMuted)
        overlay.setMuted(isMuted)
    }

    func videoOverlayDidTapFullscreen(_ overlay: VideoOverlayView) {
        toggleFullscreen()
    }

    func videoOverlayDidTapAdInfo(_ overlay: VideoOverlayView) {
        present(AdInfoViewController(), animated: true)
    }

    func videoOverlayDidTapSpeed(_ overlay: VideoOverlayView, from sourceView: UIView) {
        presentSpeedPicker(from: sourceView)
    }

    func videoOverlayDidBeginScrubbing(_ overlay: VideoOverlayView) {}

    func videoOverlay(_ overlay: VideoOverlayView, didCommitScrubTo seconds: TimeInterval) {
        resumeTarget = nil
        player.seek(to: seconds)
        lastProgress = PlaybackProgress(current: seconds, duration: lastProgress.duration, isLive: lastProgress.isLive)
        updateNowPlaying()
    }

    func videoOverlay(_ overlay: VideoOverlayView, didDoubleTapForward forward: Bool) {
        if isImmersive, let onDoubleTapToggleChat {
            onDoubleTapToggleChat()
            return
        }
        if isSeekableSource {
            skip(by: forward ? 10 : -10)
        } else {
            overlay.toggleControls()
        }
    }
}

extension VideoViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === swipeDown else { return true }
        let velocity = swipeDown.velocity(in: view)
        return abs(velocity.y) > abs(velocity.x)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === swipeDown else { return true }
        return !overlay.isScrubberTouch(touch)
    }
}
