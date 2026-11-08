import UIKit

/// Where the Apple TV app presents from.
@MainActor
enum TVRouter {
    static func topmost(from controller: UIViewController) -> UIViewController {
        var top = controller
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
