import UIKit

/// The capsule that marks an experimental feature: an ember-to-violet gradient carrying a symbol and one short word,
/// a soft glow in the same colors, a slow sheen crossing it now and then, and a press that sinks it. Tapping it opens
/// more about the feature.
@MainActor
final class ExperimentalBadge: UIControl {
    enum Style {
        /// "Experimental" with a flask, after a setting's title.
        case experimental
        /// "Hyper" with a bolt, on the player while Hyper Low Latency plays.
        case hyper

        var symbol: String {
            switch self {
            case .experimental: "flask.fill"
            case .hyper: "bolt.fill"
            }
        }

        var title: String {
            switch self {
            case .experimental: String(localized: "Experimental", comment: "Badge on a setting that is still an experiment")
            case .hyper: String(localized: "Hyper", comment: "Badge on the player while Hyper Low Latency plays")
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .experimental: String(localized: "Experimental", comment: "Badge on a setting that is still an experiment")
            case .hyper: String(localized: "Hyper Low Latency on", comment: "Spoken for the player badge while Hyper Low Latency plays")
            }
        }
    }

    /// Ember, rose and violet, the colors the badge and the Hyper Low Latency page share.
    static let colors: [UIColor] = [
        UIColor(red: 1.0, green: 0.42, blue: 0.24, alpha: 1.0),
        UIColor(red: 1.0, green: 0.31, blue: 0.60, alpha: 1.0),
        UIColor(red: 0.569, green: 0.275, blue: 1.0, alpha: 1.0),
    ]

    private let style: Style
    private let capsule = CAGradientLayer()
    private let sheen = CAGradientLayer()
    private let iconView = UIImageView()
    private let label = UILabel()
    private let content = UIStackView()
    private static let sheenKey = "sheen"

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(withDuration: isHighlighted ? 0.12 : 0.28, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
                self.alpha = self.isHighlighted ? 0.85 : 1
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        capsule.frame = bounds
        capsule.cornerRadius = bounds.height / 2
        sheen.frame = capsule.bounds
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateSheen()
    }

    /// Grows the touch area to the 44 points a finger needs while the capsule itself stays small.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let dx = max(0, (44 - bounds.width) / 2)
        let dy = max(0, (44 - bounds.height) / 2)
        return bounds.insetBy(dx: -dx, dy: -dy).contains(point)
    }

    private func build() {
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = style.accessibilityLabel

        capsule.colors = Self.colors.map(\.cgColor)
        capsule.startPoint = CGPoint(x: 0, y: 0.5)
        capsule.endPoint = CGPoint(x: 1, y: 0.5)
        capsule.masksToBounds = true
        capsule.borderWidth = 0.5
        capsule.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        layer.addSublayer(capsule)

        sheen.colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.withAlphaComponent(0.55).cgColor, UIColor.white.withAlphaComponent(0).cgColor]
        sheen.startPoint = CGPoint(x: 0, y: 0.3)
        sheen.endPoint = CGPoint(x: 1, y: 0.7)
        sheen.locations = [-0.6, -0.3, 0]
        capsule.addSublayer(sheen)

        layer.shadowColor = Self.colors[1].cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)

        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        applyText()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (badge: ExperimentalBadge, _) in badge.applyText() }

        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        content.addArrangedSubview(iconView)
        content.addArrangedSubview(label)
        content.axis = .horizontal
        content.alignment = .center
        content.spacing = 3
        content.isUserInteractionEnabled = false
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 3.5, leading: 7, bottom: 3.5, trailing: 8)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        addAction(UIAction { _ in Haptics.selection() }, for: .touchUpInside)
        NotificationCenter.default.addObserver(self, selector: #selector(reduceMotionChanged), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    /// Sets the word and the symbol at the current text size, again whenever the viewer changes it: the spaced capitals
    /// live in an attributed string, which a label does not rescale on its own.
    private func applyText() {
        let base = UIFont.systemFont(ofSize: 10, weight: .heavy)
        let font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: base, maximumPointSize: 15, compatibleWith: traitCollection)
        iconView.image = UIImage(systemName: style.symbol, withConfiguration: UIImage.SymbolConfiguration(font: font, scale: .small))
        label.attributedText = NSAttributedString(string: style.title.uppercased(), attributes: [.font: font, .kern: 0.7, .foregroundColor: UIColor.white])
    }

    @objc private func reduceMotionChanged() {
        updateSheen()
    }

    /// Sends a sheen across the capsule every few seconds while it is on screen, and none when Reduce Motion is on.
    private func updateSheen() {
        sheen.removeAnimation(forKey: Self.sheenKey)
        guard window != nil, !Motion.reduced else { return }
        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-0.6, -0.3, 0]
        sweep.toValue = [1, 1.3, 1.6]
        sweep.duration = 1.4
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let cycle = CAAnimationGroup()
        cycle.animations = [sweep]
        cycle.duration = 4.5
        cycle.repeatCount = .infinity
        cycle.beginTime = CACurrentMediaTime() + 0.6
        sheen.add(cycle, forKey: Self.sheenKey)
    }
}
