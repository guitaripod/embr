import UIKit
import EmbrCore

@MainActor
final class StreamCell: UICollectionViewCell {
    static let reuseID = "StreamCell"
    static let thumbnailWidth: CGFloat = 148

    private let thumbnail = UIImageView()
    private let liveBadge = LiveBadgeView()
    private let uptimeBadge = UptimeBadgeView()

    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private let titleLabel = UILabel()
    private let categoryLabel = UILabel()
    private let viewersLabel = UILabel()

    private let images: ImageLoading
    private var thumbTask: Task<Void, Never>?
    private var avatarTask: Task<Void, Never>?
    private var currentStreamID: String?

    override init(frame: CGRect) {
        self.images = AppContainer.shared.images
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateConfiguration(using state: UICellConfigurationState) {
        var background = UIBackgroundConfiguration.listCell().updated(for: state)
        background.backgroundColor = state.isHighlighted || state.isSelected ? Theme.surfaceElevated : .clear
        background.cornerRadius = 14
        background.backgroundInsets = NSDirectionalEdgeInsets(top: 0, leading: -6, bottom: 0, trailing: -6)
        backgroundConfiguration = background
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbTask?.cancel(); thumbTask = nil
        avatarTask?.cancel(); avatarTask = nil
        currentStreamID = nil
        thumbnail.image = nil
        avatar.image = nil
    }

    func configure(with stream: LiveStream, avatarURL: URL? = nil) {
        currentStreamID = stream.id
        nameLabel.text = stream.userName
        titleLabel.text = stream.title.isEmpty ? " " : stream.title
        let category = stream.gameName
        if stream.isMature {
            categoryLabel.text = category.isEmpty ? "🔞 Mature" : "🔞 " + category
        } else {
            categoryLabel.text = category
        }
        categoryLabel.isHidden = category.isEmpty && !stream.isMature
        viewersLabel.attributedText = Self.viewersText(stream.viewerCount)
        uptimeBadge.setStart(stream.startedAt)
        loadThumbnail(stream)
        loadAvatar(avatarURL)
        applyAccessibility(stream)
    }

    func setAvatar(url: URL?) {
        loadAvatar(url)
    }

    private static func viewersText(_ count: Int) -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let text = NSMutableAttributedString()
        if let icon = UIImage(systemName: "eye.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
            .withTintColor(Theme.liveDot, renderingMode: .alwaysOriginal) {
            let attachment = NSTextAttachment(image: icon)
            attachment.bounds = CGRect(x: 0, y: (font.capHeight - 9) / 2, width: 12, height: 9)
            text.append(NSAttributedString(attachment: attachment))
            text.append(NSAttributedString(string: " "))
        }
        text.append(NSAttributedString(string: ViewerFormat.string(count), attributes: [
            .font: font,
            .foregroundColor: Theme.secondaryText
        ]))
        return text
    }

    private func applyAccessibility(_ stream: LiveStream) {
        isAccessibilityElement = true
        accessibilityTraits = .button
        var parts = [stream.userName, "live"]
        if !stream.gameName.isEmpty { parts.append(stream.gameName) }
        parts.append("\(stream.viewerCount) viewers")
        if !stream.title.isEmpty { parts.append(stream.title) }
        if stream.isMature { parts.append("mature audiences") }
        accessibilityLabel = parts.joined(separator: ", ")
    }

    private func loadThumbnail(_ stream: LiveStream) {
        let scale = UIScreen.main.scale
        guard let url = stream.thumbnailURL(width: Int(Self.thumbnailWidth * scale), height: Int(Self.thumbnailWidth * scale * 9 / 16)) else { return }
        if let cached = images.cachedImage(for: url) { thumbnail.image = cached; return }
        let targetID = stream.id
        thumbTask?.cancel()
        thumbTask = Task { [weak self] in
            let image = await self?.images.image(for: url, targetScale: scale)
            guard let self, !Task.isCancelled, self.currentStreamID == targetID else { return }
            self.thumbnail.image = image
        }
    }

    private func loadAvatar(_ url: URL?) {
        avatarTask?.cancel()
        guard let url else { avatar.image = nil; return }
        if let cached = images.cachedImage(for: url) { avatar.image = cached; return }
        let targetID = currentStreamID
        avatarTask = Task { [weak self] in
            let image = await self?.images.image(for: url, targetScale: UIScreen.main.scale)
            guard let self, !Task.isCancelled, self.currentStreamID == targetID else { return }
            self.avatar.image = image
        }
    }

    private func setUp() {
        contentView.backgroundColor = .clear

        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        thumbnail.backgroundColor = Theme.surface
        thumbnail.layer.cornerRadius = 10
        thumbnail.layer.cornerCurve = .continuous

        for badge in [liveBadge, uptimeBadge] {
            badge.translatesAutoresizingMaskIntoConstraints = false
        }

        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.backgroundColor = Theme.surfaceElevated
        avatar.layer.cornerRadius = 9

        nameLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = Theme.primaryText
        nameLabel.numberOfLines = 1

        titleLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13, weight: .regular))
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.secondaryText
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        categoryLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12, weight: .semibold))
        categoryLabel.adjustsFontForContentSizeCategory = true
        categoryLabel.textColor = Theme.accent
        categoryLabel.numberOfLines = 1
        categoryLabel.lineBreakMode = .byTruncatingTail

        viewersLabel.setContentHuggingPriority(.required, for: .horizontal)
        viewersLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let nameRow = UIStackView(arrangedSubviews: [avatar, nameLabel])
        nameRow.axis = .horizontal
        nameRow.alignment = .center
        nameRow.spacing = 6

        let metaRow = UIStackView(arrangedSubviews: [categoryLabel, viewersLabel])
        metaRow.axis = .horizontal
        metaRow.alignment = .center
        metaRow.spacing = 8

        let textColumn = UIStackView(arrangedSubviews: [nameRow, titleLabel, metaRow])
        textColumn.axis = .vertical
        textColumn.alignment = .fill
        textColumn.spacing = 3
        textColumn.setCustomSpacing(4, after: titleLabel)
        textColumn.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(thumbnail)
        thumbnail.addSubview(liveBadge)
        thumbnail.addSubview(uptimeBadge)
        contentView.addSubview(textColumn)

        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnail.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: Self.thumbnailWidth),
            thumbnail.heightAnchor.constraint(equalTo: thumbnail.widthAnchor, multiplier: 9.0 / 16.0),
            thumbnail.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),

            liveBadge.topAnchor.constraint(equalTo: thumbnail.topAnchor, constant: 5),
            liveBadge.leadingAnchor.constraint(equalTo: thumbnail.leadingAnchor, constant: 5),

            uptimeBadge.bottomAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: -5),
            uptimeBadge.trailingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: -5),

            avatar.widthAnchor.constraint(equalToConstant: 18),
            avatar.heightAnchor.constraint(equalToConstant: 18),

            textColumn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 1),
            textColumn.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 10),
            textColumn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            textColumn.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
    }
}

enum ViewerFormat {
    static func string(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return String(count)
    }
}

@MainActor
private final class LiveBadgeView: UIView {
    private let dot = UIImageView()
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        backgroundColor = Theme.liveDot
        layer.cornerRadius = 4
        layer.cornerCurve = .continuous

        dot.image = UIImage(systemName: "dot.radiowaves.left.and.right")
        dot.tintColor = .white
        dot.contentMode = .scaleAspectFit
        if !Motion.reduced { dot.addSymbolEffect(.pulse, options: .repeating) }

        label.text = "LIVE"
        label.font = .systemFont(ofSize: 10, weight: .heavy)
        label.textColor = .white

        let stack = UIStackView(arrangedSubviews: [dot, label])
        stack.axis = .horizontal
        stack.spacing = 3
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 2, leading: 5, bottom: 2, trailing: 5)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

@MainActor
private final class UptimeBadgeView: UIView {
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.6)
        layer.cornerRadius = 4
        layer.cornerCurve = .continuous

        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setStart(_ start: Date) {
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { isHidden = true; return }
        isHidden = false
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        label.text = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
