import UIKit
import EmbrCore

/// The capsule on a supporter's profile and channel page: their flame in their color and "Founding Supporter #12".
final class SupporterTag: UIView {
    private let flame = UIImageView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        #if os(tvOS)
        let height: CGFloat = 52
        label.font = .systemFont(ofSize: 26, weight: .semibold)
        #else
        let height: CGFloat = 30
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        #endif
        layer.cornerRadius = height / 2
        layer.cornerCurve = .continuous
        flame.contentMode = .scaleAspectFit
        let row = UIStackView(arrangedSubviews: [flame, label])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = height * 0.2
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height),
            flame.widthAnchor.constraint(equalToConstant: height * 0.62),
            flame.heightAnchor.constraint(equalToConstant: height * 0.62),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: height * 0.36),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -height * 0.46),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isAccessibilityElement = true
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Shows the tag for a Twitch user id the directory lists as a supporter, and hides it for everyone else.
    func show(userID: String) {
        guard let look = SupporterDirectory.shared.look(for: userID) else {
            isHidden = true
            return
        }
        flame.image = look.color.flameImage
        label.text = look.number.map { String(localized: "Founding Supporter #\($0)") } ?? String(localized: "Founding Supporter")
        label.textColor = Theme.readableNameColor(look.color.color)
        backgroundColor = look.color.color.withAlphaComponent(0.16)
        accessibilityLabel = label.text
        isHidden = false
    }
}
