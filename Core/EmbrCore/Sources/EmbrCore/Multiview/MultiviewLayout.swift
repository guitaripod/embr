import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Where each stream of a multiview goes. Every tile keeps the 16:9 shape of a stream, the arrangement is the largest
/// that fits the bounds, and it is centred in them.
///
/// - One stream fills the bounds.
/// - Two sit side by side.
/// - Three or four with a featured stream put it large on the left and the others stacked on the right.
/// - Four without a featured stream form a 2x2 grid.
public enum MultiviewLayout {
    public static let maximumStreams = 4
    private static let aspect: Double = 16.0 / 9.0

    public static func frames(count: Int, featured: Int?, in bounds: CGRect, spacing: CGFloat) -> [CGRect] {
        guard count > 0, bounds.width > 0, bounds.height > 0 else { return [] }
        let count = min(count, maximumStreams)
        let featured = featured.flatMap { (0..<count).contains($0) ? $0 : nil }
        var unitSpacing = 0.0
        var frames = unitFrames(count: count, featured: featured, spacing: unitSpacing)
        for _ in 0..<4 {
            unitSpacing = Double(spacing) / scale(of: frames, in: bounds)
            frames = unitFrames(count: count, featured: featured, spacing: unitSpacing)
        }
        return fit(frames, in: bounds)
    }

    /// How much `frames` grow to fill `bounds`. The arrangement is laid out with spacing in its own units, so the
    /// spacing in points is converted through this scale until the two agree.
    private static func scale(of frames: [CGRect], in bounds: CGRect) -> Double {
        let union = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        return Double(min(bounds.width / union.width, bounds.height / union.height))
    }

    /// The arrangement at an arbitrary scale, laid out at a small-tile width of 1 plus `spacing`.
    private static func unitFrames(count: Int, featured: Int?, spacing: Double) -> [CGRect] {
        switch count {
        case 1:
            return [tile(x: 0, y: 0, width: 1)]
        case 2:
            return [tile(x: 0, y: 0, width: 1), tile(x: 1 + spacing, y: 0, width: 1)]
        case 4 where featured == nil:
            let height = 1 / aspect
            return [
                tile(x: 0, y: 0, width: 1),
                tile(x: 1 + spacing, y: 0, width: 1),
                tile(x: 0, y: height + spacing, width: 1),
                tile(x: 1 + spacing, y: height + spacing, width: 1),
            ]
        default:
            return featuredFrames(count: count, featured: featured ?? 0, spacing: spacing)
        }
    }

    /// One large tile and `count - 1` small ones stacked beside it, the large one exactly as tall as the stack.
    private static func featuredFrames(count: Int, featured: Int, spacing: Double) -> [CGRect] {
        let small = count - 1
        let smallHeight = 1 / aspect
        let largeHeight = Double(small) * smallHeight + Double(small - 1) * spacing
        let largeWidth = largeHeight * aspect
        var frames: [CGRect] = []
        var stackIndex = 0
        for index in 0..<count {
            if index == featured {
                frames.append(tile(x: 0, y: 0, width: largeWidth))
            } else {
                let y = Double(stackIndex) * (smallHeight + spacing)
                frames.append(tile(x: largeWidth + spacing, y: y, width: 1))
                stackIndex += 1
            }
        }
        return frames
    }

    private static func tile(x: Double, y: Double, width: Double) -> CGRect {
        CGRect(x: x, y: y, width: width, height: width / aspect)
    }

    /// Scales the arrangement to the largest size that fits `bounds` and centres it.
    private static func fit(_ frames: [CGRect], in bounds: CGRect) -> [CGRect] {
        let union = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        let scale = min(bounds.width / union.width, bounds.height / union.height)
        let width = union.width * scale
        let height = union.height * scale
        let originX = bounds.minX + (bounds.width - width) / 2
        let originY = bounds.minY + (bounds.height - height) / 2
        return frames.map { frame in
            let x: CGFloat = originX + (frame.minX - union.minX) * scale
            let y: CGFloat = originY + (frame.minY - union.minY) * scale
            return CGRect(x: x.rounded(), y: y.rounded(), width: (frame.width * scale).rounded(), height: (frame.height * scale).rounded())
        }
    }
}
