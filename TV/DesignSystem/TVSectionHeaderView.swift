import UIKit

final class TVSectionHeaderView: UICollectionReusableView {
    static let kind = "TVSectionHeader"
    static let reuseID = "TVSectionHeaderView"

    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = TVFont.sectionTitle
        titleLabel.textColor = Theme.primaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        accessibilityTraits = .header
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String) {
        titleLabel.text = title
        accessibilityLabel = title
    }
}
