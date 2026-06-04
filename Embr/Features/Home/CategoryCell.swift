import UIKit
import EmbrCore

@MainActor
final class CategoryCell: UICollectionViewCell {
    static let reuseID = "CategoryCell"

    private let boxArt = UIImageView()
    private let nameLabel = UILabel()

    private let images: ImageLoading
    private var imageTask: Task<Void, Never>?
    private var currentCategoryID: String?

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
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.95, y: 0.95) : .identity
                self.alpha = self.isHighlighted ? 0.88 : 1
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        currentCategoryID = nil
        boxArt.image = nil
    }

    func configure(with category: GameCategory) {
        currentCategoryID = category.id
        nameLabel.text = category.name
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = category.name
        loadBoxArt(category)
    }

    private func loadBoxArt(_ category: GameCategory) {
        let scale = UIScreen.main.scale
        let width = Int(144 * scale)
        let height = Int(192 * scale)
        guard let url = category.boxArtURL(width: width, height: height) else { return }
        if let cached = images.cachedImage(for: url) {
            boxArt.image = cached
            return
        }
        let targetID = category.id
        imageTask?.cancel()
        imageTask = Task { [weak self] in
            let image = await self?.images.image(for: url, targetScale: scale)
            guard let self, !Task.isCancelled, self.currentCategoryID == targetID else { return }
            self.boxArt.image = image
        }
    }

    private func setUp() {
        contentView.backgroundColor = .clear

        boxArt.translatesAutoresizingMaskIntoConstraints = false
        boxArt.contentMode = .scaleAspectFill
        boxArt.clipsToBounds = true
        boxArt.backgroundColor = Theme.surface
        boxArt.layer.cornerRadius = 8
        boxArt.layer.cornerCurve = .continuous

        nameLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13, weight: .semibold))
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = Theme.primaryText
        nameLabel.numberOfLines = 2
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(boxArt)
        contentView.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            boxArt.topAnchor.constraint(equalTo: contentView.topAnchor),
            boxArt.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            boxArt.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            boxArt.heightAnchor.constraint(equalTo: boxArt.widthAnchor, multiplier: 4.0 / 3.0),

            nameLabel.topAnchor.constraint(equalTo: boxArt.bottomAnchor, constant: 6),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -6)
        ])
    }
}
