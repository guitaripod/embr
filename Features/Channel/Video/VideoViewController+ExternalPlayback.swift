import AVKit
import UIKit

extension VideoViewController {
    private static let externalRouteEndGrace: TimeInterval = 1.0

    var isPlayingExternally: Bool { externalRoute != nil }

    /// A TV taking the picture shows at once. One giving it back is believed only after a moment, since AirPlay can drop
    /// out for an instant while the stream reloads, and a channel page showing only chat stops the stream when it ends.
    func externalRouteDidChange(_ route: ExternalRoute?) {
        guard route == nil, externalRoute != nil else {
            applyExternalRoute(route)
            return
        }
        guard externalRouteEndWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.applyExternalRoute(nil) }
        externalRouteEndWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.externalRouteEndGrace, execute: work)
    }

    /// While a TV has the picture the video area says where the stream plays, keeps its controls up and offers no
    /// picture in picture. A TV giving the picture back while the app is away leaves the stream as leaving the app does.
    func applyExternalRoute(_ route: ExternalRoute?) {
        externalRouteEndWork?.cancel()
        externalRouteEndWork = nil
        guard route != externalRoute else { return }
        externalRoute = route
        overlay.setExternalPlayback(route?.playingOnText)
        overlay.setPictureInPictureEnabled(
            route == nil && player is HLSVideoPlayer && AVPictureInPictureController.isPictureInPictureSupported()
        )
        if route == nil, UIApplication.shared.applicationState == .background {
            handleBackground()
        }
        onExternalRouteChanged?(route)
    }

    #if DEBUG
    /// `-screenshotExternal <device name>` poses the page as if that TV had the picture, for a capture without one.
    func applyScreenshotExternalRoute() {
        guard let name = ScreenshotRouter.option("External") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.applyExternalRoute(ExternalRoute(deviceName: name))
        }
    }
    #endif
}
