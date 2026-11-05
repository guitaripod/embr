import UIKit
import EmbrCore

/// A live stream card: the stream's current picture with the LIVE badge, and the channel, title and game below it.
/// While it stays focused it can host a muted live preview (``TVLivePreview``) on top of the picture.
final class TVStreamCell: UICollectionViewCell {
    static let reuseID = "TVStreamCell"

    let artwork = TVArtworkView(placeholderSymbol: "play.tv")
    /// Where ``TVLivePreview`` puts its video layer; it moves with the artwork's focus effect.
    let previewContainer = UIView()
    private let badge = TVLiveBadge()
    private let favoriteMark = UIImageView(image: UIImage(systemName: "star.fill"))
    private let nameLabel = UILabel()
    private let titleLabel = UILabel()
    private let gameLabel = UILabel()
    private var artworkHeight: NSLayoutConstraint!
    private(set) var stream: LiveStream?

    override init(frame: CGRect) {
        super.init(frame: frame)
        artwork.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(artwork)

        let overlay = artwork.overlayContentView
        previewContainer.backgroundColor = .clear
        previewContainer.layer.cornerRadius = TVMetrics.cornerRadius
        previewContainer.layer.cornerCurve = .continuous
        previewContainer.layer.masksToBounds = true
        previewContainer.isUserInteractionEnabled = false
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(previewContainer)

        badge.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(badge)

        favoriteMark.tintColor = .systemYellow
        favoriteMark.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)
        favoriteMark.layer.shadowColor = UIColor.black.cgColor
        favoriteMark.layer.shadowOpacity = 0.6
        favoriteMark.layer.shadowRadius = 6
        favoriteMark.layer.shadowOffset = .zero
        favoriteMark.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(favoriteMark)

        nameLabel.font = TVFont.cardTitle
        nameLabel.textColor = Theme.primaryText
        titleLabel.font = TVFont.cardSubtitle
        titleLabel.textColor = Theme.secondaryText
        gameLabel.font = TVFont.cardSubtitle
        gameLabel.textColor = Theme.secondaryText.withAlphaComponent(0.7)
        [nameLabel, titleLabel, gameLabel].forEach { $0.lineBreakMode = .byTruncatingTail }

        let caption = UIStackView(arrangedSubviews: [nameLabel, titleLabel, gameLabel])
        caption.axis = .vertical
        caption.spacing = 2
        caption.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(caption)

        let inset = TVMetrics.Card.badgeInset
        artworkHeight = artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor, multiplier: 9.0 / 16.0)
        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: contentView.topAnchor),
            artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            artworkHeight,

            previewContainer.topAnchor.constraint(equalTo: overlay.topAnchor),
            previewContainer.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
            previewContainer.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),

            badge.topAnchor.constraint(equalTo: overlay.topAnchor, constant: inset),
            badge.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: inset),

            favoriteMark.topAnchor.constraint(equalTo: overlay.topAnchor, constant: inset),
            favoriteMark.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -inset),

            caption.topAnchor.constraint(equalTo: artwork.focusedFrameGuide.bottomAnchor, constant: TVMetrics.captionSpacing),
            caption.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            caption.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ stream: LiveStream, isFavorite: Bool, featured: Bool) {
        self.stream = stream
        let size = featured ? TVMetrics.Card.featured : TVMetrics.Card.stream
        artwork.setImage(TVStreamThumbnail.url(for: stream, size: size))
        badge.configure(viewers: stream.viewerCount)
        favoriteMark.isHidden = !isFavorite
        nameLabel.font = featured ? TVFont.bold(.headline) : TVFont.cardTitle
        nameLabel.text = stream.userName.isEmpty ? stream.userLogin : stream.userName
        titleLabel.text = stream.title
        gameLabel.text = stream.gameName
        gameLabel.isHidden = stream.gameName.isEmpty
        accessibilityLabel = [nameLabel.text, String(localized: "Live"), stream.title, stream.gameName]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        accessibilityValue = String(localized: "\(stream.viewerCount.formatted()) viewers")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        TVLivePreview.shared.detach(from: self)
        artwork.reset()
        stream = nil
    }
}

/// Twitch's stream thumbnails change every few minutes behind one URL; a query that changes every five minutes makes
/// the image cache fetch the current one.
enum TVStreamThumbnail {
    static func url(for stream: LiveStream, size: CGSize) -> URL? {
        guard let url = stream.thumbnailURL(width: Int(size.width * 1.5), height: Int(size.height * 1.5)),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let slot = Int(Date().timeIntervalSince1970 / 300)
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "t", value: String(slot))]
        return components.url
    }
}
