import UIKit

/// The red LIVE pill with the viewer count, drawn on stream artwork.
final class TVLiveBadge: UIView {
    private let dot = UIView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.62)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous

        dot.backgroundColor = Theme.liveDot
        dot.layer.cornerRadius = 6
        dot.translatesAutoresizingMaskIntoConstraints = false

        label.font = TVFont.badge
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [dot, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 12),
            dot.heightAnchor.constraint(equalToConstant: 12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(viewers: Int?) {
        if let viewers {
            label.text = String(localized: "LIVE · \(viewers.formatted(.number.notation(.compactName)))", comment: "Badge on a live stream: LIVE and the viewer count")
            accessibilityLabel = String(localized: "Live, \(viewers.formatted()) viewers")
        } else {
            label.text = String(localized: "LIVE", comment: "Badge on a live channel")
            accessibilityLabel = String(localized: "Live")
        }
    }
}
