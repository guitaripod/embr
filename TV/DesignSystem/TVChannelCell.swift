import UIKit

/// A channel by its round avatar, with a red ring and dot while it is live.
final class TVChannelCell: UICollectionViewCell {
    static let reuseID = "TVChannelCell"

    private let artwork = TVArtworkView(shape: .circle, placeholderSymbol: "person.fill")
    private let liveDot = UIView()
    private let nameLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        artwork.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(artwork)

        liveDot.backgroundColor = Theme.liveDot
        liveDot.layer.cornerRadius = 14
        liveDot.layer.borderWidth = 4
        liveDot.layer.borderColor = Theme.background.cgColor
        liveDot.translatesAutoresizingMaskIntoConstraints = false
        artwork.overlayContentView.addSubview(liveDot)

        nameLabel.font = TVFont.cardSubtitle
        nameLabel.textColor = Theme.primaryText
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        let overlay = artwork.overlayContentView
        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: contentView.topAnchor),
            artwork.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            artwork.widthAnchor.constraint(equalToConstant: TVMetrics.Card.avatar),
            artwork.heightAnchor.constraint(equalToConstant: TVMetrics.Card.avatar),
            liveDot.widthAnchor.constraint(equalToConstant: 28),
            liveDot.heightAnchor.constraint(equalToConstant: 28),
            liveDot.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -14),
            liveDot.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -14),
            nameLabel.topAnchor.constraint(equalTo: artwork.focusedFrameGuide.bottomAnchor, constant: TVMetrics.captionSpacing),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ channel: TVChannelSummary) {
        artwork.setImage(channel.avatarURL)
        liveDot.isHidden = !channel.isLive
        nameLabel.text = channel.displayName
        accessibilityLabel = channel.isLive
            ? String(localized: "\(channel.displayName), live")
            : channel.displayName
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        liveDot.layer.borderColor = Theme.background.resolvedColor(with: traitCollection).cgColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artwork.reset()
    }
}
