import UIKit
import EmbrCore

/// A past broadcast or a clip: its thumbnail with the duration, and the title and age below.
final class TVVideoCell: UICollectionViewCell {
    static let reuseID = "TVVideoCell"

    private let artwork = TVArtworkView(placeholderSymbol: "film")
    private let durationLabel = TVPaddedLabel()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        artwork.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(artwork)

        durationLabel.font = TVFont.badge
        durationLabel.textColor = .white
        durationLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        durationLabel.layer.cornerRadius = 8
        durationLabel.layer.masksToBounds = true
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        artwork.overlayContentView.addSubview(durationLabel)

        titleLabel.font = TVFont.cardTitle
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 2
        detailLabel.font = TVFont.cardSubtitle
        detailLabel.textColor = Theme.secondaryText

        let caption = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        caption.axis = .vertical
        caption.spacing = 2
        caption.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(caption)

        let overlay = artwork.overlayContentView
        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: contentView.topAnchor),
            artwork.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            artwork.heightAnchor.constraint(equalTo: artwork.widthAnchor, multiplier: 9.0 / 16.0),
            durationLabel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -TVMetrics.Card.badgeInset),
            durationLabel.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -TVMetrics.Card.badgeInset),
            caption.topAnchor.constraint(equalTo: artwork.focusedFrameGuide.bottomAnchor, constant: TVMetrics.captionSpacing),
            caption.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            caption.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ video: VideoOnDemand) {
        let size = TVMetrics.Card.video
        let template = video.thumbnailURLTemplate
            .replacingOccurrences(of: "%{width}", with: String(Int(size.width * 1.5)))
            .replacingOccurrences(of: "%{height}", with: String(Int(size.height * 1.5)))
        artwork.setImage(URL(string: template))
        durationLabel.text = TVDuration.text(seconds: video.durationSeconds)
        titleLabel.text = video.title
        detailLabel.text = [
            video.createdAt.formatted(.relative(presentation: .named)),
            String(localized: "\(video.viewCount.formatted(.number.notation(.compactName))) views"),
        ].joined(separator: " · ")
        accessibilityLabel = [video.title, detailLabel.text, durationLabel.accessibilityLabel].compactMap { $0 }.joined(separator: ", ")
    }

    func configure(_ clip: Clip) {
        artwork.setImage(clip.thumbnailURL)
        durationLabel.text = TVDuration.text(seconds: Int(clip.duration.rounded()))
        titleLabel.text = clip.title
        detailLabel.text = [
            clip.creatorName,
            String(localized: "\(clip.viewCount.formatted(.number.notation(.compactName))) views"),
        ].filter { !$0.isEmpty }.joined(separator: " · ")
        accessibilityLabel = [clip.title, detailLabel.text].compactMap { $0 }.joined(separator: ", ")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artwork.reset()
    }
}

final class TVPaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

enum TVDuration {
    static func text(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let rest = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}
