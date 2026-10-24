import UIKit

/// The seam between video and the chat column on iPad: a hairline with a grip, wide enough to
/// catch a finger, highlighted under the pointer, and adjustable with VoiceOver.
@MainActor
final class ColumnDividerView: UIView {
    static let hitWidth: CGFloat = 16

    var onAccessibilityAdjust: ((CGFloat) -> Void)?

    private let line = UIView()
    private let grip = UIView()

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        line.backgroundColor = Theme.surfaceElevated
        line.translatesAutoresizingMaskIntoConstraints = false
        grip.backgroundColor = Theme.secondaryText.withAlphaComponent(0.45)
        grip.layer.cornerRadius = 2.5
        grip.layer.cornerCurve = .continuous
        grip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        addSubview(grip)
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: topAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.centerXAnchor.constraint(equalTo: centerXAnchor),
            line.widthAnchor.constraint(equalToConstant: 1),
            grip.centerXAnchor.constraint(equalTo: centerXAnchor),
            grip.centerYAnchor.constraint(equalTo: centerYAnchor),
            grip.widthAnchor.constraint(equalToConstant: 5),
            grip.heightAnchor.constraint(equalToConstant: 44)
        ])
        addInteraction(UIPointerInteraction(delegate: self))
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Chat width")
        accessibilityTraits = .adjustable
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setDragging(_ dragging: Bool) {
        UIView.animate(withDuration: 0.15) {
            self.grip.backgroundColor = dragging ? Theme.accent : Theme.secondaryText.withAlphaComponent(0.45)
            self.grip.transform = dragging ? CGAffineTransform(scaleX: 1.4, y: 1.2) : .identity
        }
    }

    override func accessibilityIncrement() {
        onAccessibilityAdjust?(40)
    }

    override func accessibilityDecrement() {
        onAccessibilityAdjust?(-40)
    }
}

extension ColumnDividerView: UIPointerInteractionDelegate {
    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        UIPointerStyle(effect: .highlight(UITargetedPreview(view: grip)))
    }
}
