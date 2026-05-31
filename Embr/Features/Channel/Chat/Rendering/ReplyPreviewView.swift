import UIKit
import EmbrCore

final class ReplyPreviewView: UIView {
    private let hookLayer = CAShapeLayer()
    private let label = UILabel()

    private let hookWidth: CGFloat = 12
    private let hookInset: CGFloat = 4

    override init(frame: CGRect) {
        super.init(frame: frame)
        hookLayer.fillColor = UIColor.clear.cgColor
        hookLayer.strokeColor = Theme.secondaryText.withAlphaComponent(0.6).cgColor
        hookLayer.lineWidth = 1.5
        hookLayer.lineCap = .round
        layer.addSublayer(hookLayer)

        label.font = .systemFont(ofSize: 11)
        label.textColor = Theme.secondaryText
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hookWidth + hookInset + 4),
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
                .font: UIFont.boldSystemFont(ofSize: 11),
                .foregroundColor: Theme.secondaryText,
            ]
        )
        text.append(NSAttributedString(
            string: reply.parentText,
            attributes: [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: Theme.secondaryText,
            ]
        ))
        label.attributedText = text
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath()
        let bottom = bounds.height - hookInset
        path.move(to: CGPoint(x: hookInset, y: bottom))
        path.addLine(to: CGPoint(x: hookInset, y: bounds.midY))
        path.addQuadCurve(
            to: CGPoint(x: hookInset + hookWidth, y: hookInset),
            controlPoint: CGPoint(x: hookInset, y: hookInset)
        )
        hookLayer.path = path.cgPath
        hookLayer.strokeColor = Theme.secondaryText.withAlphaComponent(0.6).cgColor
    }
}
