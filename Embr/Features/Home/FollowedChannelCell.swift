import UIKit
import EmbrCore

@MainActor
final class FollowedChannelCell: UICollectionViewCell {
    static let reuseID = "FollowedChannelCell"

    private let avatar = UIImageView()
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
    private let row = UIStackView()

    /// In an iPad column grid the row starts on the layout margin with the cards above it, and
    /// its highlight reaches outside the row instead.
    var alignsWithMargins = false {
        didSet {
            guard alignsWithMargins != oldValue else { return }
            let inset: CGFloat = alignsWithMargins ? 0 : 14
            row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 5, leading: inset, bottom: 5, trailing: inset)
            setNeedsUpdateConfiguration()
        }
    }

    private let images: ImageLoading
    private var imageTask: Task<Void, Never>?
    private var currentID: String?

    override init(frame: CGRect) {
        self.images = AppContainer.shared.images
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateConfiguration(using state: UICellConfigurationState) {
        var background = UIBackgroundConfiguration.listCell().updated(for: state)
        background.backgroundColor = state.isHighlighted ? Theme.surfaceElevated : .clear
        background.cornerRadius = 10
        let inset: CGFloat = alignsWithMargins ? -8 : 8
        background.backgroundInsets = NSDirectionalEdgeInsets(top: 2, leading: inset, bottom: 2, trailing: inset)
        backgroundConfiguration = background
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        currentID = nil
        avatar.image = nil
    }

    func configure(with channel: FollowedChannel, avatarURL: URL?) {
        currentID = channel.id
        let name = channel.broadcasterName.isEmpty ? channel.broadcasterLogin : channel.broadcasterName
        nameLabel.text = name
        statusLabel.text = String(localized: "Offline")
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = String(localized: "\(name), offline")
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
        hoverStyle = UIHoverStyle(effect: .highlight, shape: .rect(cornerRadius: 10))
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.backgroundColor = Theme.surface
        avatar.layer.cornerRadius = 18

        nameLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 16, weight: .semibold))
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = Theme.primaryText

        statusLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13, weight: .regular))
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = Theme.secondaryText

        let labels = UIStackView(arrangedSubviews: [nameLabel, statusLabel])
        labels.axis = .vertical
        labels.spacing = 1

        chevron.tintColor = Theme.secondaryText
        chevron.contentMode = .scaleAspectFit
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)

        row.addArrangedSubview(avatar)
        row.addArrangedSubview(labels)
        row.addArrangedSubview(chevron)
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14)
        contentView.addSubview(row)

        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 36),
            avatar.heightAnchor.constraint(equalToConstant: 36),
            row.topAnchor.constraint(equalTo: contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }
}
