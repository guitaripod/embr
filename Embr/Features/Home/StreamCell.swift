import UIKit
import EmbrCore

@MainActor
final class StreamCell: UICollectionViewCell {
    static let reuseID = "StreamCell"

    private let thumbnail = UIImageView()
    private let liveBadge = LiveBadgeView()
    private let viewerBadge = ViewerCountView()
    private let uptimeBadge = UptimeBadgeView()
    private let titleLabel = UILabel()
    private let userLabel = UILabel()
    private let gameLabel = UILabel()

    private let images: ImageLoading
    private var imageTask: Task<Void, Never>?
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
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
                self.alpha = self.isHighlighted ? 0.88 : 1
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        currentStreamID = nil
        thumbnail.image = nil
    }

    func configure(with stream: LiveStream) {
        currentStreamID = stream.id
        titleLabel.text = stream.title
        userLabel.text = stream.userName
        let game = stream.isMature ? "🔞 " + stream.gameName : stream.gameName
        gameLabel.text = stream.gameName.isEmpty ? (stream.isMature ? "🔞 Mature" : nil) : game
        gameLabel.isHidden = stream.gameName.isEmpty && !stream.isMature
        liveBadge.isHidden = false
        viewerBadge.setCount(stream.viewerCount)
        uptimeBadge.setStart(stream.startedAt)
        loadThumbnail(stream)

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
        let width = Int(360 * scale)
        let height = Int(202 * scale)
        guard let url = stream.thumbnailURL(width: width, height: height) else { return }
        if let cached = images.cachedImage(for: url) {
            thumbnail.image = cached
            return
        }
        let targetID = stream.id
        imageTask?.cancel()
        imageTask = Task { [weak self] in
            let image = await self?.images.image(for: url, targetScale: scale)
            guard let self, !Task.isCancelled, self.currentStreamID == targetID else { return }
            self.thumbnail.image = image
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

        titleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.primaryText
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        userLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13, weight: .regular))
        userLabel.adjustsFontForContentSizeCategory = true
        userLabel.textColor = Theme.secondaryText
        userLabel.numberOfLines = 1

        gameLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12, weight: .regular))
        gameLabel.adjustsFontForContentSizeCategory = true
        gameLabel.textColor = Theme.secondaryText
        gameLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [titleLabel, userLabel, gameLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        liveBadge.translatesAutoresizingMaskIntoConstraints = false
        viewerBadge.translatesAutoresizingMaskIntoConstraints = false
        uptimeBadge.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(thumbnail)
        thumbnail.addSubview(liveBadge)
        thumbnail.addSubview(viewerBadge)
        thumbnail.addSubview(uptimeBadge)
        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnail.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnail.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnail.heightAnchor.constraint(equalTo: thumbnail.widthAnchor, multiplier: 9.0 / 16.0),

            liveBadge.topAnchor.constraint(equalTo: thumbnail.topAnchor, constant: 8),
            liveBadge.leadingAnchor.constraint(equalTo: thumbnail.leadingAnchor, constant: 8),
            liveBadge.trailingAnchor.constraint(lessThanOrEqualTo: thumbnail.trailingAnchor, constant: -8),

            viewerBadge.bottomAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: -8),
            viewerBadge.leadingAnchor.constraint(equalTo: thumbnail.leadingAnchor, constant: 8),
            viewerBadge.trailingAnchor.constraint(lessThanOrEqualTo: thumbnail.trailingAnchor, constant: -8),

            uptimeBadge.topAnchor.constraint(equalTo: thumbnail.topAnchor, constant: 8),
            uptimeBadge.trailingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: -8),

            textStack.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 8),
            textStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
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
        dot.addSymbolEffect(.pulse, options: .repeating)

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
        backgroundColor = UIColor.black.withAlphaComponent(0.7)
        layer.cornerRadius = 4
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
        backgroundColor = UIColor.black.withAlphaComponent(0.7)
        layer.cornerRadius = 4
        layer.cornerCurve = .continuous

        icon.image = UIImage(systemName: "person.fill")
        icon.tintColor = .white
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
            icon.widthAnchor.constraint(equalToConstant: 10),
            icon.heightAnchor.constraint(equalToConstant: 10)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setCount(_ count: Int) {
        label.text = Self.format(count)
    }

    private static func format(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return String(count)
    }
}
