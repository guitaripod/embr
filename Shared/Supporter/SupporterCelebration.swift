import UIKit

/// The moment someone becomes a Founding Supporter: sparks fly up from the flame in their color and the flame swells
/// once. With Reduce Motion on, the flame only brightens.
enum SupporterCelebration {
    @MainActor
    static func play(from flame: UIView, color: UIColor) {
        guard let container = flame.superview?.window ?? flame.superview else { return }
        guard !UIAccessibility.isReduceMotionEnabled else {
            flame.alpha = 0.55
            UIView.animate(withDuration: 0.6) { flame.alpha = 1 }
            return
        }
        UIView.animate(withDuration: 0.18, animations: {
            flame.transform = CGAffineTransform(scaleX: 1.14, y: 1.14)
        }, completion: { _ in
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 0.6) {
                flame.transform = .identity
            }
        })

        let center = flame.convert(CGPoint(x: flame.bounds.midX, y: flame.bounds.maxY * 0.62), to: container)
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = center
        emitter.emitterShape = .circle
        emitter.emitterSize = CGSize(width: flame.bounds.width * 0.3, height: flame.bounds.width * 0.3)
        emitter.renderMode = .additive
        emitter.emitterCells = [spark(color: color, scale: 1), spark(color: .white, scale: 0.6), spark(color: color.withAlphaComponent(0.8), scale: 1.4)]
        container.layer.addSublayer(emitter)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            emitter.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            emitter.removeFromSuperlayer()
        }
    }

    private static func spark(color: UIColor, scale: CGFloat) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = sparkImage.cgImage
        cell.birthRate = 70
        cell.lifetime = 1.8
        cell.lifetimeRange = 0.6
        cell.velocity = 260 * scale
        cell.velocityRange = 140
        cell.emissionLongitude = -.pi / 2
        cell.emissionRange = .pi / 1.6
        cell.yAcceleration = 160
        cell.scale = 0.22 * scale
        cell.scaleRange = 0.12
        cell.scaleSpeed = -0.1
        cell.alphaSpeed = -0.55
        cell.color = color.cgColor
        return cell
    }

    private static let sparkImage: UIImage = {
        let size = CGSize(width: 48, height: 48)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            let middle = CGPoint(x: size.width / 2, y: size.height / 2)
            context.cgContext.drawRadialGradient(gradient, startCenter: middle, startRadius: 0, endCenter: middle, endRadius: size.width / 2, options: [])
        }
    }()
}
