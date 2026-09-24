import UIKit
import EmbrCore

/// A live stream as a card: the thumbnail across the full width, the channel beneath it. The
/// iPad grids use it wherever a phone shows a `StreamCell` row.
@MainActor
final class StreamCardCell: UICollectionViewCell {
    private let thumbnail = UIImageView()
    private let liveBadge = CardBadge(style: .live)
    private let viewersBadge = CardBadge(style: .dark)
    private let uptimeBadge = CardBadge(style: .dark)

    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private let titleLabel = UILabel()
    private let categoryLabel = UILabel()

    private let images: ImageLoading
    private var thumbTask: Task<Void, Never>?
    private var avatarTask: Task<Void, Never>?
    private var currentStreamID: String?
    private var thumbnailWidth: CGFloat = 0
    private var stream: LiveStream?

    override init(frame: CGRect) {
        self.images = AppContainer.shared.images
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.contentView.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
                self.contentView.alpha = self.isHighlighted ? 0.85 : 1
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbTask?.cancel(); thumbTask = nil
        avatarTask?.cancel(); avatarTask = nil
        currentStreamID = nil
        stream = nil
        thumbnail.image = nil
        avatar.image = nil
        contentView.transform = .identity
        contentView.alpha = 1
    }

    /// The thumbnail is requested once the card knows its width, at the size it is drawn, so a
    /// wide card on a large iPad is not a blown-up phone thumbnail. The thumbnail spans the card,
    /// so the cell's own width stands in for it before its subviews are laid out.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let stream, thumbnailWidth != Self.pixelWidth(bounds.width, scale: displayScale) else { return }
        loadThumbnail(stream)
    }

    func configure(with stream: LiveStream, avatarURL: URL? = nil) {
        let isNewStream = currentStreamID != stream.id
        currentStreamID = stream.id
        self.stream = stream
        nameLabel.text = stream.userName
        titleLabel.text = stream.title.isEmpty ? " " : stream.title
        let category = stream.gameName
        if stream.isMature {
            categoryLabel.text = category.isEmpty ? String(localized: "🔞 Mature") : "🔞 " + category
        } else {
            categoryLabel.text = category.isEmpty ? " " : category
        }
        viewersBadge.setText(String(localized: "\(ViewerFormat.string(stream.viewerCount)) viewers"))
        let elapsed = Date().timeIntervalSince(stream.startedAt)
        uptimeBadge.isHidden = elapsed <= 0
        if elapsed > 0 {
            let hours = Int(elapsed) / 3600
            let minutes = (Int(elapsed) % 3600) / 60
            uptimeBadge.setText(hours > 0 ? String(localized: "\(hours)h \(minutes)m") : String(localized: "\(minutes)m"))
        }
        if isNewStream {
            thumbnailWidth = 0
            thumbnail.image = nil
        }
        if bounds.width > 0 { loadThumbnail(stream) }
        loadAvatar(avatarURL)
        applyAccessibility(stream)
    }

    private func applyAccessibility(_ stream: LiveStream) {
        isAccessibilityElement = true
        accessibilityTraits = .button
        var parts = [stream.userName, String(localized: "live")]
        if !stream.gameName.isEmpty { parts.append(stream.gameName) }
        parts.append(String(localized: "\(stream.viewerCount) viewers"))
        if !stream.title.isEmpty { parts.append(stream.title) }
        if stream.isMature { parts.append(String(localized: "mature audiences")) }
        accessibilityLabel = parts.joined(separator: ", ")
    }

    private var displayScale: CGFloat {
        traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
    }

    /// Widths are rounded up to 160-pixel steps so neighbouring card sizes share cached images.
    private static func pixelWidth(_ points: CGFloat, scale: CGFloat) -> CGFloat {
        guard points > 0 else { return 0 }
        return (points * scale / 160).rounded(.up) * 160
    }

    private func loadThumbnail(_ stream: LiveStream) {
        let width = Self.pixelWidth(bounds.width, scale: displayScale)
        guard width > 0, let url = stream.thumbnailURL(width: Int(width), height: Int(width * 9 / 16)) else { return }
        thumbnailWidth = width
        if let cached = images.cachedImage(for: url) { thumbnail.image = cached; return }
        let targetID = stream.id
        let scale = displayScale
        thumbTask?.cancel()
        thumbTask = Task { [weak self] in
            let image = await self?.images.image(for: url, targetScale: scale)
            guard let self, !Task.isCancelled, self.currentStreamID == targetID, let image else { return }
            self.thumbnail.image = image
        }
    }

    private func loadAvatar(_ url: URL?) {
        avatarTask?.cancel()
        guard let url else { avatar.image = nil; return }
        if let cached = images.cachedImage(for: url) { avatar.image = cached; return }
        let targetID = currentStreamID
        let scale = displayScale
        avatarTask = Task { [weak self] in
            let image = await self?.images.image(for: url, targetScale: scale)
            guard let self, !Task.isCancelled, self.currentStreamID == targetID else { return }
            self.avatar.image = image
        }
    }

    private func setUp() {
        hoverStyle = UIHoverStyle(effect: .highlight, shape: .rect(cornerRadius: 16))

        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        thumbnail.backgroundColor = Theme.surface
        thumbnail.layer.cornerRadius = 12
        thumbnail.layer.cornerCurve = .continuous

        for badge in [liveBadge, viewersBadge, uptimeBadge] {
            badge.translatesAutoresizingMaskIntoConstraints = false
            thumbnail.addSubview(badge)
        }
        liveBadge.setText(String(localized: "LIVE"))

        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.backgroundColor = Theme.surfaceElevated
        avatar.layer.cornerRadius = 18

        nameLabel.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = Theme.primaryText

        titleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 13, weight: .regular))
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.secondaryText
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        categoryLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12, weight: .semibold))
        categoryLabel.adjustsFontForContentSizeCategory = true
        categoryLabel.textColor = Theme.accent

        let text = UIStackView(arrangedSubviews: [nameLabel, titleLabel, categoryLabel])
        text.axis = .vertical
        text.spacing = 2
        text.setCustomSpacing(4, after: titleLabel)
        text.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(thumbnail)
        contentView.addSubview(avatar)
        contentView.addSubview(text)

        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnail.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnail.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnail.heightAnchor.constraint(equalTo: thumbnail.widthAnchor, multiplier: 9.0 / 16.0),

            liveBadge.topAnchor.constraint(equalTo: thumbnail.topAnchor, constant: 8),
            liveBadge.leadingAnchor.constraint(equalTo: thumbnail.leadingAnchor, constant: 8),
            viewersBadge.bottomAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: -8),
            viewersBadge.leadingAnchor.constraint(equalTo: thumbnail.leadingAnchor, constant: 8),
            uptimeBadge.bottomAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: -8),
            uptimeBadge.trailingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: -8),

            avatar.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 10),
            avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 36),
            avatar.heightAnchor.constraint(equalToConstant: 36),

            text.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 9),
            text.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10),
            text.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            text.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4)
        ])
    }
}

/// A small rounded label pinned over a card thumbnail: the red LIVE tag, or a dark tag for the
/// viewer count and uptime.
@MainActor
private final class CardBadge: UIView {
    enum Style { case live, dark }

    private let label = UILabel()

    init(style: Style) {
        super.init(frame: .zero)
        layer.cornerRadius = 5
        layer.cornerCurve = .continuous
        switch style {
        case .live:
            backgroundColor = Theme.liveDot
            label.font = .systemFont(ofSize: 11, weight: .heavy)
        case .dark:
            backgroundColor = UIColor.black.withAlphaComponent(0.62)
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        }
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        ])
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setText(_ text: String) {
        label.text = text
    }
}
