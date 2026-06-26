import UIKit
import EmbrCore

@MainActor
final class RecentChannelCell: UICollectionViewCell {
    static let reuseID = "RecentChannelCell"

    private let avatar = UIImageView()
    private let nameLabel = UILabel()

    private let images: ImageLoading
    private var imageTask: Task<Void, Never>?
    private var currentID: String?

    override init(frame: CGRect) {
        self.images = AppContainer.shared.images
        super.init(frame: frame)
        setUp()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: RecentChannelCell, _) in
            cell.avatar.layer.borderColor = Theme.surfaceElevated.resolvedColor(with: cell.traitCollection).cgColor
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        currentID = nil
        avatar.image = nil
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(withDuration: 0.16, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.avatar.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
                self.alpha = self.isHighlighted ? 0.85 : 1
            }
        }
    }

    func configure(with channel: WatchedChannel, avatarURL: URL?) {
        currentID = channel.id
        nameLabel.text = channel.displayName
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = channel.displayName
        avatar.image = nil
        guard let url = avatarURL else { return }
        if let cached = images.cachedImage(for: url) {
            avatar.image = cached
            return
        }
        let target = channel.id
        imageTask?.cancel()
        imageTask = Task { [weak self] in
            let image = await self?.images.image(for: url, targetScale: UIScreen.main.scale)
            guard let self, !Task.isCancelled, self.currentID == target else { return }
            self.avatar.image = image
        }
    }

    private func setUp() {
        contentView.backgroundColor = .clear

        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.backgroundColor = Theme.surface
        avatar.layer.cornerRadius = 28
        avatar.layer.borderWidth = 1
        avatar.layer.borderColor = Theme.surfaceElevated.resolvedColor(with: traitCollection).cgColor

        nameLabel.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 11, weight: .medium))
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.maximumContentSizeCategory = .extraExtraExtraLarge
        nameLabel.textColor = Theme.secondaryText
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail

        let stack = UIStackView(arrangedSubviews: [avatar, nameLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 56),
            avatar.heightAnchor.constraint(equalToConstant: 56),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            nameLabel.widthAnchor.constraint(equalTo: contentView.widthAnchor)
        ])
    }
}

@MainActor
final class SectionHeaderView: UICollectionReusableView {
    static let elementKind = "section-header"
    static let reuseID = "SectionHeaderView"

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = Theme.secondaryText
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String) {
        label.text = title
    }
}
