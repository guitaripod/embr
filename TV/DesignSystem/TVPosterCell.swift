import UIKit
import EmbrCore

/// A category's box art with its name below.
final class TVPosterCell: UICollectionViewCell {
    static let reuseID = "TVPosterCell"

    private let artwork = TVArtworkView(placeholderSymbol: "gamecontroller")
    private let nameLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        artwork.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(artwork)
        nameLabel.font = TVFont.cardSubtitle
        nameLabel.textColor = Theme.primaryText
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)
        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: contentView.topAnchor),
            artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor, multiplier: 4.0 / 3.0),
            nameLabel.topAnchor.constraint(equalTo: artwork.focusedFrameGuide.bottomAnchor, constant: TVMetrics.captionSpacing),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ category: GameCategory) {
        let size = TVMetrics.Card.poster
        artwork.setImage(category.boxArtURL(width: Int(size.width * 1.5), height: Int(size.height * 1.5)))
        nameLabel.text = category.name
        accessibilityLabel = category.name
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artwork.reset()
    }
}
