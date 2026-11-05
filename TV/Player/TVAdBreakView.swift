import UIKit

/// Covers the picture while Twitch plays an ad break, which Embr drops from the stream: a ring that empties until the
/// stream resumes. Chat keeps running beside it.
final class TVAdBreakView: UIView {
    private let ring = CAShapeLayer()
    private let track = CAShapeLayer()
    private let secondsLabel = UILabel()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let ringView = UIView()
    private var total: TimeInterval = 0
    private var announced = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.88)
        alpha = 0
        isHidden = true
        isUserInteractionEnabled = false

        ringView.translatesAutoresizingMaskIntoConstraints = false
        track.strokeColor = UIColor.white.withAlphaComponent(0.15).cgColor
        ring.strokeColor = Theme.accent.cgColor
        for layer in [track, ring] {
            layer.fillColor = UIColor.clear.cgColor
            layer.lineWidth = 10
            layer.lineCap = .round
            ringView.layer.addSublayer(layer)
        }

        secondsLabel.font = TVFont.mono(size: 52, weight: .bold)
        secondsLabel.textColor = .white
        secondsLabel.textAlignment = .center
        secondsLabel.translatesAutoresizingMaskIntoConstraints = false
        ringView.addSubview(secondsLabel)

        titleLabel.text = String(localized: "Ad break", comment: "Title of the screen shown while Twitch plays an ad")
        titleLabel.font = TVFont.bold(.title3)
        titleLabel.textColor = .white
        messageLabel.text = String(localized: "The stream picks up right after it. Chat keeps going.")
        messageLabel.font = TVFont.body
        messageLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [ringView, titleLabel, messageLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 24
        stack.setCustomSpacing(40, after: ringView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            ringView.widthAnchor.constraint(equalToConstant: 180),
            ringView.heightAnchor.constraint(equalToConstant: 180),
            secondsLabel.centerXAnchor.constraint(equalTo: ringView.centerXAnchor),
            secondsLabel.centerYAnchor.constraint(equalTo: ringView.centerYAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 800),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath(
            arcCenter: CGPoint(x: 90, y: 90), radius: 80,
            startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true
        ).cgPath
        track.path = path
        ring.path = path
    }

    /// Shows the remaining seconds, or hides the cover when `remaining` is nil.
    func update(remaining: TimeInterval?) {
        guard let remaining else {
            total = 0
            announced = false
            setVisible(false)
            return
        }
        total = max(total, remaining)
        secondsLabel.text = String(max(1, Int(remaining.rounded(.up))))
        ring.strokeColor = Theme.accent.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeEnd = total > 0 ? CGFloat(remaining / total) : 1
        CATransaction.commit()
        setVisible(true)
        if !announced {
            announced = true
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Ad break. The stream resumes in \(Int(remaining.rounded(.up))) seconds."))
        }
    }

    private func setVisible(_ visible: Bool) {
        if visible, isHidden {
            isHidden = false
        }
        UIView.animate(withDuration: TVMetrics.Duration.fade, animations: {
            self.alpha = visible ? 1 : 0
        }, completion: { _ in
            if !visible { self.isHidden = true }
        })
    }
}
