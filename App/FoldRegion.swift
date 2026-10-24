import UIKit

/// Where the fold of a foldable phone cuts a view while the device is partly open, in the view's
/// own coordinates and including the margin around the crease that content keeps clear of.
nonisolated enum FoldRegion: Equatable, Sendable {
    case vertical(minX: CGFloat, maxX: CGFloat)
    case horizontal(minY: CGFloat, maxY: CGFloat)

    var thickness: CGFloat {
        switch self {
        case .vertical(let minX, let maxX): return maxX - minX
        case .horizontal(let minY, let maxY): return maxY - minY
        }
    }
}

@MainActor
enum Fold {
    /// The active fold across `view`, or nil on a display without one and while the device is flat.
    /// Read on every layout pass: the system reports regions after the first pass and never again
    /// by itself, and an empty answer means only that nothing is reported yet.
    static func region(in view: UIView) -> FoldRegion? {
        #if canImport(UIKit, _version: 9127.0.85)
        if #available(iOS 27.1, *) {
            let regions = view.reservedRegions(kind: .division)
            guard let region = regions.first(where: \.isActive) else { return nil }
            let frame = region.frame
            if frame.height >= view.bounds.height - 1, frame.width < view.bounds.width {
                return .vertical(minX: frame.minX, maxX: frame.maxX)
            }
            if frame.width >= view.bounds.width - 1, frame.height < view.bounds.height {
                return .horizontal(minY: frame.minY, maxY: frame.maxY)
            }
        }
        #endif
        return nil
    }

    /// Rebuilds a grid's layout whenever the hinge moves, so its columns divide on the fold.
    static func invalidateLayout(of collectionView: UICollectionView) {
        #if canImport(UIKit, _version: 9127.0.85)
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { [weak collectionView] _, _ in
                collectionView?.collectionViewLayout.invalidateLayout()
            }
            collectionView.addInteraction(interaction)
        }
        #endif
    }

    /// Asks `view` to lay out again whenever the hinge moves, since a change of pose alone does not
    /// resize anything. Only the fact of a change is used; the angle never drives a layout.
    static func relayout(_ view: UIView) {
        #if canImport(UIKit, _version: 9127.0.85)
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { [weak view] _, _ in
                view?.setNeedsLayout()
                view?.layoutIfNeeded()
            }
            view.addInteraction(interaction)
        }
        #endif
    }
}
