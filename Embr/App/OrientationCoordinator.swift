import UIKit

/// The phone browses in portrait and turns to landscape only while a video is on screen. iPad
/// windows resize freely, so every orientation is always allowed there. Everything that depends on
/// the idiom or the scene's orientation lives in this file, so layout code can ask for room instead.
@MainActor
enum OrientationCoordinator {
    static var phoneMask: UIInterfaceOrientationMask = .portrait

    /// The shortest side a phone-idiom window needs before the tablet arrangement fits: both
    /// displays of a foldable phone's inner screen clear it, a phone turned on its side does not.
    private static let tabletMinimumSide: CGFloat = 600

    static var mask: UIInterfaceOrientationMask {
        isPhone ? phoneMask : .all
    }

    static var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    /// Whether a window of this size is laid out like an iPad window: side by side columns, cards,
    /// fullscreen by hiding chrome rather than by turning the device. Decided from the room there
    /// is, never from the model, so an iPad in a narrow split and a foldable's outer display both
    /// get the compact arrangement.
    static func usesTabletLayout(for size: CGSize) -> Bool {
        !isPhone || min(size.width, size.height) >= tabletMinimumSide
    }

    static func isLandscape(_ scene: UIWindowScene?) -> Bool {
        scene?.interfaceOrientation.isLandscape ?? false
    }

    static func rotate(_ scene: UIWindowScene, to orientations: UIInterfaceOrientationMask, onFailure: ((Error) -> Void)? = nil) {
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { error in
            onFailure?(error)
        }
    }
}
