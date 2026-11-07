import UIKit
import EmbrCore

/// The line above a reply naming the message it answers, joined to the reply below by a curved connector that starts
/// over the reply's first badge or name.
final class ReplyPreviewView: UIView {
    private let hookLayer = CAShapeLayer()
    private let label = UILabel()

    private let hookX: CGFloat = 6
    private let hookReach: CGFloat = 10
    private let textGap: CGFloat = 6

    #if os(tvOS)
    private static let fontSize: CGFloat = 11
    #else
    private static let fontSize: CGFloat = 12
    #endif

    override init(frame: CGRect) {
        super.init(frame: frame)
        hookLayer.fillColor = UIColor.clear.cgColor
        hookLayer.lineWidth = 1.5
        hookLayer.lineCap = .round
        hookLayer.lineJoin = .round
        layer.addSublayer(hookLayer)

        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hookX + hookReach + textGap),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with reply: ReplyContext) {
        let text = NSMutableAttributedString(
            string: "@\(reply.parentDisplayName) ",
            attributes: [
                .font: UIFont.systemFont(ofSize: Self.fontSize, weight: .semibold),
                .foregroundColor: Theme.secondaryText,
            ]
        )
        text.append(NSAttributedString(
            string: reply.parentText,
            attributes: [
                .font: UIFont.systemFont(ofSize: Self.fontSize),
                .foregroundColor: Theme.secondaryText,
            ]
        ))
        label.attributedText = text
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath()
        let mid = bounds.midY
        let radius: CGFloat = 5
        path.move(to: CGPoint(x: hookX, y: bounds.height + 2))
        path.addLine(to: CGPoint(x: hookX, y: mid + radius))
        path.addQuadCurve(to: CGPoint(x: hookX + radius, y: mid), controlPoint: CGPoint(x: hookX, y: mid))
        path.addLine(to: CGPoint(x: hookX + hookReach, y: mid))
        hookLayer.path = path.cgPath
        hookLayer.strokeColor = UIColor.tertiaryLabel.resolvedColor(with: traitCollection).cgColor
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsLayout()
    }
}
