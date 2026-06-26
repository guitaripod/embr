import UIKit
import EmbrCore

@MainActor
final class StreamCell: UICollectionViewCell {
    static let reuseID = "StreamCell"

    private let thumbnail = UIImageView()
    private let scrim = CAGradientLayer()
    private let liveBadge = LiveBadgeView()
    private let viewerBadge = ViewerCountView()
    private let uptimeBadge = UptimeBadgeView()

    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private let titleLabel = UILabel()
    private let categoryPill = PillLabel()

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
        background.backgroundColor = .clear
        backgroundConfiguration = background
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.thumbnail.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
                self.contentView.alpha = self.isHighlighted ? 0.9 : 1
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrim.frame = thumbnail.bounds
        CATransaction.commit()
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
        let category = stream.gameName.isEmpty ? "" : stream.gameName
        if stream.isMature {
            categoryPill.text = category.isEmpty ? "🔞 Mature" : "🔞 " + category
        } else {
            categoryPill.text = category
        }
        categoryPill.isHidden = category.isEmpty && !stream.isMature
        viewerBadge.setCount(stream.viewerCount)
        uptimeBadge.setStart(stream.startedAt)
        loadThumbnail(stream)
        loadAvatar(avatarURL)
        applyAccessibility(stream)
    }

    func setAvatar(url: URL?) {
        loadAvatar(url)
    }

    private func applyAccessibility(_ stream: LiveStream) {
        isAccessibilityElement = true
        accessibilityTraits = .button
        var parts = [stream.userName, "live"]
        if !stream.title.isEmpty { parts.append(stream.title) }
        if !stream.gameName.isEmpty { parts.append(stream.gameName) }
        parts.append("\(stream.viewerCount) viewers")
        if stream.isMature { parts.append("mature audiences") }
        accessibilityLabel = parts.joined(separator: ", ")
    }

    private func loadThumbnail(_ stream: LiveStream) {
        let scale = UIScreen.main.scale
        guard let url = stream.thumbnailURL(width: Int(440 * scale), height: Int(248 * scale)) else { return }
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
        thumbnail.layer.cornerRadius = 12
        thumbnail.layer.cornerCurve = .continuous

        scrim.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.55).cgColor]
        scrim.locations = [0.55, 1.0]
        thumbnail.layer.addSublayer(scrim)

        for badge in [liveBadge, viewerBadge, uptimeBadge] {
            badge.translatesAutoresizingMaskIntoConstraints = false
        }

        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.backgroundColor = Theme.surfaceElevated
        avatar.layer.cornerRadius = 20
        avatar.layer.borderWidth = 1.5
        avatar.layer.borderColor = Theme.accent.cgColor

        nameLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .bold))
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = Theme.primaryText
        nameLabel.numberOfLines = 1

        titleLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13, weight: .regular))
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.secondaryText
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        let textColumn = UIStackView(arrangedSubviews: [nameLabel, titleLabel, categoryPill])
        textColumn.axis = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 3

        let infoRow = UIStackView(arrangedSubviews: [avatar, textColumn])
        infoRow.axis = .horizontal
        infoRow.alignment = .center
        infoRow.spacing = 10
        infoRow.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(thumbnail)
        thumbnail.addSubview(liveBadge)
        thumbnail.addSubview(viewerBadge)
        thumbnail.addSubview(uptimeBadge)
        contentView.addSubview(infoRow)

        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnail.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnail.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnail.heightAnchor.constraint(equalTo: thumbnail.widthAnchor, multiplier: 9.0 / 16.0),

            liveBadge.topAnchor.constraint(equalTo: thumbnail.topAnchor, constant: 8),
            liveBadge.leadingAnchor.constraint(equalTo: thumbnail.leadingAnchor, constant: 8),

            viewerBadge.bottomAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: -8),
            viewerBadge.leadingAnchor.constraint(equalTo: thumbnail.leadingAnchor, constant: 8),

            uptimeBadge.bottomAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: -8),
            uptimeBadge.trailingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: -8),

            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40),

            infoRow.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 10),
            infoRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            infoRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            infoRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
}

@MainActor
private final class PillLabel: UILabel {
    private let insets = UIEdgeInsets(top: 2, left: 7, bottom: 2, right: 7)

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 11, weight: .semibold))
        adjustsFontForContentSizeCategory = true
        textColor = Theme.accent
        backgroundColor = Theme.accent.withAlphaComponent(0.14)
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        numberOfLines = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

@MainActor
private final class LiveBadgeView: UIView {
    private let dot = UIImageView()
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        backgroundColor = Theme.liveDot
        layer.cornerRadius = 5
        layer.cornerCurve = .continuous

        dot.image = UIImage(systemName: "dot.radiowaves.left.and.right")
        dot.tintColor = .white
        dot.contentMode = .scaleAspectFit
        if !Motion.reduced { dot.addSymbolEffect(.pulse, options: .repeating) }

        label.text = "LIVE"
        label.font = .systemFont(ofSize: 11, weight: .heavy)
        label.textColor = .white

        let stack = UIStackView(arrangedSubviews: [dot, label])
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            dot.widthAnchor.constraint(equalToConstant: 11),
            dot.heightAnchor.constraint(equalToConstant: 11)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

@MainActor
private final class UptimeBadgeView: UIView {
    private let icon = UIImageView()
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.55)
        layer.cornerRadius = 5
        layer.cornerCurve = .continuous

        icon.image = UIImage(systemName: "clock")
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit

        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            icon.widthAnchor.constraint(equalToConstant: 10),
            icon.heightAnchor.constraint(equalToConstant: 10)
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

@MainActor
private final class ViewerCountView: UIView {
    private let icon = UIImageView()
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.55)
        layer.cornerRadius = 5
        layer.cornerCurve = .continuous

        icon.image = UIImage(systemName: "person.fill")
        icon.tintColor = Theme.liveDot
        icon.contentMode = .scaleAspectFit

        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            icon.widthAnchor.constraint(equalToConstant: 11),
            icon.heightAnchor.constraint(equalToConstant: 11)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setCount(_ count: Int) {
        label.text = Self.format(count)
    }

    private static func format(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return String(count)
    }
}
