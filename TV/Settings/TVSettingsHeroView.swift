import UIKit

/// The left half of Settings, in the Apple TV's own style: a large picture, the name of the section in focus and what
/// it does. It changes with a cross-fade as focus moves between sections.
final class TVSettingsHeroView: UIView {
    enum Picture: Equatable {
        case symbol(String)
        case flame(SupporterAccent)
    }

    struct Content: Equatable {
        let picture: Picture
        let title: String
        let detail: String?
    }

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private var shown: Content?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 200, weight: .regular)
            .applying(UIImage.SymbolConfiguration(hierarchicalColor: Theme.accent))

        titleLabel.font = TVFont.bold(.title3)
        titleLabel.textColor = Theme.primaryText
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        detailLabel.font = TVFont.body
        detailLabel.textColor = Theme.secondaryText
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [imageView, titleLabel, detailLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
        stack.setCustomSpacing(44, after: imageView)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 280),
            imageView.heightAnchor.constraint(equalToConstant: 280),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ content: Content, animated: Bool) {
        guard content != shown else { return }
        let first = shown == nil
        shown = content
        guard animated, !first, !UIAccessibility.isReduceMotionEnabled else {
            apply(content)
            return
        }
        UIView.transition(with: self, duration: TVMetrics.Duration.fade, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.apply(content)
        }
    }

    /// Repaints the symbol in the current accent, after a supporter picks another one.
    func refreshAccent() {
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 200, weight: .regular)
            .applying(UIImage.SymbolConfiguration(hierarchicalColor: Theme.accent))
    }

    private func apply(_ content: Content) {
        switch content.picture {
        case .symbol(let name): imageView.image = UIImage(systemName: name)
        case .flame(let color): imageView.image = color.flameImage
        }
        titleLabel.text = content.title
        detailLabel.text = content.detail
        detailLabel.isHidden = content.detail == nil
    }
}
