import UIKit
import EmbrCore

final class BadgeStripView: UIView {
    private let stack = UIStackView()
    private var imageViews: [UIImageView] = []
    private let images: ImageLoading
    private var loadTasks: [Task<Void, Never>] = []
    private let badgeSize: CGFloat

    init(images: ImageLoading = ImageLoader.shared, badgeSize: CGFloat = 18) {
        self.images = images
        self.badgeSize = badgeSize
        super.init(frame: .zero)
        stack.axis = .horizontal
        stack.spacing = 3
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with badges: [Badge]) {
        cancelLoads()
        for view in imageViews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        imageViews.removeAll(keepingCapacity: true)

        for badge in badges {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: badgeSize),
                imageView.heightAnchor.constraint(equalToConstant: badgeSize),
            ])
            stack.addArrangedSubview(imageView)
            imageViews.append(imageView)

            let task = Task { [weak imageView, images] in
                let image = await images.badgeImage(for: badge, scale: .x2)
                guard !Task.isCancelled else { return }
                imageView?.image = image
            }
            loadTasks.append(task)
        }
    }

    func prepareForReuse() {
        cancelLoads()
        for view in imageViews { view.image = nil }
    }

    private func cancelLoads() {
        for task in loadTasks { task.cancel() }
        loadTasks.removeAll(keepingCapacity: true)
    }
}
