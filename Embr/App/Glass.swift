import UIKit

@MainActor
enum Glass {
    /// A Liquid Glass background view (iOS 26+) to place behind content, with a
    /// material fallback on older systems. Add content to the returned view's
    /// `contentView`, or place it behind sibling content.
    static func view(cornerRadius: CGFloat = 0, tint: UIColor? = nil, interactive: Bool = false) -> UIVisualEffectView {
        let effectView: UIVisualEffectView
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            glass.tintColor = tint
            glass.isInteractive = interactive
            effectView = UIVisualEffectView(effect: glass)
        } else {
            effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
            if let tint {
                effectView.contentView.backgroundColor = tint.withAlphaComponent(0.18)
            }
        }
        effectView.translatesAutoresizingMaskIntoConstraints = false
        if cornerRadius > 0 {
            effectView.layer.cornerRadius = cornerRadius
            effectView.layer.cornerCurve = .continuous
            effectView.clipsToBounds = true
        }
        return effectView
    }

    /// Whether real Liquid Glass is available; useful to drop opaque fills that
    /// would otherwise defeat the translucency.
    static var isAvailable: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
}
