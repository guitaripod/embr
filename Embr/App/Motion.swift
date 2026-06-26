import UIKit

enum Motion {
    @MainActor static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }
}
